use serde::{Deserialize, Serialize};

/// 单字/词时间戳
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct LyricWord {
    /// 词/字文本
    pub text: String,
    /// 起始时间戳（毫秒）
    pub start_ms: u64,
    /// 持续时间（毫秒）
    pub duration_ms: u64,
}

/// 单行歌词
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct LyricLine {
    /// 时间戳（毫秒）
    pub time_ms: u64,
    /// 歌词文本（纯净文本，移除了时间标签）
    pub text: String,
    /// 逐字时间戳列表（可选）
    pub words: Option<Vec<LyricWord>>,
}

/// 歌词数据
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Lyrics {
    /// 歌词行列表（按时间排序）
    pub lines: Vec<LyricLine>,
}

impl Lyrics {
    /// 从 LRC 格式文本解析歌词（支持标准 LRC、增强型逐字 LRC 以及常见括号逐字格式）
    pub fn parse_lrc(lrc_text: &str) -> Self {
        let mut lines = Vec::new();
        let mut global_offset: i64 = 0;

        for raw_line in lrc_text.lines() {
            let line = raw_line.trim();
            if line.is_empty() {
                continue;
            }

            // 检查全局 offset 标签，例如 [offset:+200] 或 [offset:-150]
            if line.starts_with("[offset:") && line.ends_with(']') {
                let offset_str = &line[8..line.len() - 1].trim();
                if let Ok(offset_val) = offset_str.parse::<i64>() {
                    global_offset = offset_val;
                }
                continue;
            }

            // 提取所有行级时间标签 [mm:ss.xx]
            let chars: Vec<char> = line.chars().collect();
            let mut i = 0;
            let mut text_start = 0;
            let mut timestamps = Vec::new();

            while i < chars.len() {
                if chars[i] == '[' {
                    if let Some(end) = chars[i + 1..].iter().position(|&c| c == ']') {
                        let tag_content: String = chars[i + 1..i + 1 + end].iter().collect();
                        if let Some(ms) = Self::parse_time_tag(&tag_content) {
                            timestamps.push(ms);
                            i = i + 1 + end + 1;
                            text_start = i;
                        } else {
                            // 可能是元数据标签如 [ti:xxx] 或 YRC 行时间 [83450,3200]
                            // 尝试解析 [start_ms, duration_ms] 格式
                            if let Some(ms) = Self::parse_yrc_line_tag(&tag_content) {
                                timestamps.push(ms);
                                i = i + 1 + end + 1;
                                text_start = i;
                            } else {
                                // 非时间标签，跳过该行或继续
                                break;
                            }
                        }
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            }

            // 歌词内容
            let raw_content: String = chars[text_start..].iter().collect();
            let raw_content = raw_content.trim();
            if raw_content.is_empty() && timestamps.is_empty() {
                continue;
            }

            // 尝试解析逐字时间戳
            let (clean_text, words) = Self::parse_words(raw_content);

            if clean_text.is_empty() && words.is_none() {
                continue;
            }

            // 如果有时间戳，按时间戳添加行
            if !timestamps.is_empty() {
                for ms in timestamps {
                    lines.push(LyricLine {
                        time_ms: ms,
                        text: clean_text.clone(),
                        words: words.clone(),
                    });
                }
            } else if let Some(ref w_list) = words {
                // 如果没有行时间戳，但逐字中有时间，以第一个字的时间为行时间
                if let Some(first_w) = w_list.first() {
                    lines.push(LyricLine {
                        time_ms: first_w.start_ms,
                        text: clean_text,
                        words: words.clone(),
                    });
                }
            }
        }

        // 应用全局 offset
        if global_offset != 0 {
            for line in &mut lines {
                line.time_ms = ((line.time_ms as i64) + global_offset).max(0) as u64;
                if let Some(ref mut words) = line.words {
                    for w in words {
                        w.start_ms = ((w.start_ms as i64) + global_offset).max(0) as u64;
                    }
                }
            }
        }

        // 按时间排序
        lines.sort_by_key(|l| l.time_ms);

        Lyrics { lines }
    }

    /// 解析逐字信息：支持 <mm:ss.xx> 或 <ms> 尖括号格式，以及 (start, dur) 括号格式
    fn parse_words(content: &str) -> (String, Option<Vec<LyricWord>>) {
        // 先检查是否包含尖括号 <...> 逐字标记
        if content.contains('<') && content.contains('>') {
            let mut words = Vec::new();
            let mut clean_text = String::new();
            let chars: Vec<char> = content.chars().collect();
            let mut i = 0;
            let mut last_tag_time: Option<u64> = None;
            let mut current_word_text = String::new();

            while i < chars.len() {
                if chars[i] == '<' {
                    if let Some(end) = chars[i + 1..].iter().position(|&c| c == '>') {
                        let tag_str: String = chars[i + 1..i + 1 + end].iter().collect();
                        let tag_time = Self::parse_time_tag(&tag_str)
                            .or_else(|| tag_str.parse::<u64>().ok());

                        if let Some(time) = tag_time {
                            // 如果之前已经有字和开始时间，结束上一个字
                            if let Some(prev_start) = last_tag_time {
                                if !current_word_text.is_empty() {
                                    let duration = time.saturating_sub(prev_start).max(1);
                                    words.push(LyricWord {
                                        text: current_word_text.clone(),
                                        start_ms: prev_start,
                                        duration_ms: duration,
                                    });
                                    clean_text.push_str(&current_word_text);
                                    current_word_text.clear();
                                }
                            }
                            last_tag_time = Some(time);
                            i = i + 1 + end + 1;
                            continue;
                        }
                    }
                }

                current_word_text.push(chars[i]);
                i += 1;
            }

            // 处理末尾遗留的字
            if let Some(prev_start) = last_tag_time {
                if !current_word_text.is_empty() {
                    // 最后一个字若没有闭合标签，默认分配 400ms 持续时间
                    let default_duration = 400u64;
                    words.push(LyricWord {
                        text: current_word_text.clone(),
                        start_ms: prev_start,
                        duration_ms: default_duration,
                    });
                    clean_text.push_str(&current_word_text);
                }
            }

            if !words.is_empty() {
                return (clean_text, Some(words));
            }
        }

        // 再检查是否为 YRC / KRC 风格的括号逐字标记：(start, duration, ...)文本
        if content.contains('(') && content.contains(')') {
            let mut words = Vec::new();
            let mut clean_text = String::new();
            let chars: Vec<char> = content.chars().collect();
            let mut i = 0;
            let mut current_start = None;
            let mut current_dur = None;
            let mut current_word_text = String::new();

            while i < chars.len() {
                if chars[i] == '(' {
                    if let Some(end) = chars[i + 1..].iter().position(|&c| c == ')') {
                        let tag_str: String = chars[i + 1..i + 1 + end].iter().collect();
                        let parts: Vec<&str> = tag_str.split(',').collect();
                        if parts.len() >= 2 {
                            if let (Ok(s), Ok(d)) = (parts[0].trim().parse::<u64>(), parts[1].trim().parse::<u64>()) {
                                // 保存上一个收集的字
                                if let (Some(prev_s), Some(prev_d)) = (current_start, current_dur) {
                                    if !current_word_text.is_empty() {
                                        words.push(LyricWord {
                                            text: current_word_text.clone(),
                                            start_ms: prev_s,
                                            duration_ms: prev_d,
                                        });
                                        clean_text.push_str(&current_word_text);
                                        current_word_text.clear();
                                    }
                                }
                                current_start = Some(s);
                                current_dur = Some(d);
                                i = i + 1 + end + 1;
                                continue;
                            }
                        }
                    }
                }
                current_word_text.push(chars[i]);
                i += 1;
            }

            // 最后一个字
            if let (Some(prev_s), Some(prev_d)) = (current_start, current_dur) {
                if !current_word_text.is_empty() {
                    words.push(LyricWord {
                        text: current_word_text.clone(),
                        start_ms: prev_s,
                        duration_ms: prev_d,
                    });
                    clean_text.push_str(&current_word_text);
                }
            }

            if !words.is_empty() {
                return (clean_text, Some(words));
            }
        }

        // 普通文本，无逐字标记
        (content.to_string(), None)
    }

    /// 解析时间标签 "mm:ss.xx" 或 "mm:ss.xxx" 为毫秒
    fn parse_time_tag(tag: &str) -> Option<u64> {
        let parts: Vec<&str> = tag.split(':').collect();
        if parts.len() != 2 {
            return None;
        }

        let minutes: u64 = parts[0].trim().parse().ok()?;
        let sec_parts: Vec<&str> = parts[1].split('.').collect();
        if sec_parts.is_empty() {
            return None;
        }

        let seconds: u64 = sec_parts[0].trim().parse().ok()?;
        let millis = if sec_parts.len() > 1 {
            let ms_str = sec_parts[1].trim();
            let ms: u64 = ms_str.parse().ok()?;
            if ms_str.len() == 2 {
                ms * 10
            } else if ms_str.len() == 1 {
                ms * 100
            } else {
                ms
            }
        } else {
            0
        };

        Some(minutes * 60 * 1000 + seconds * 1000 + millis)
    }

    /// 解析 YRC 格式的行时间 [start_ms, duration_ms]
    fn parse_yrc_line_tag(tag: &str) -> Option<u64> {
        let parts: Vec<&str> = tag.split(',').collect();
        if parts.len() >= 2 {
            parts[0].trim().parse().ok()
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_standard_lrc() {
        let lrc = "[00:01.00]第一行\n[00:05.50]第二行";
        let parsed = Lyrics::parse_lrc(lrc);
        assert_eq!(parsed.lines.len(), 2);
        assert_eq!(parsed.lines[0].time_ms, 1000);
        assert_eq!(parsed.lines[0].text, "第一行");
        assert!(parsed.lines[0].words.is_none());
    }

    #[test]
    fn test_parse_enhanced_lrc() {
        let lrc = "[01:23.45]<01:23.45>哪<01:23.75>怕<01:24.00>只<01:24.40>有<01:25.00>";
        let parsed = Lyrics::parse_lrc(lrc);
        assert_eq!(parsed.lines.len(), 1);
        let line = &parsed.lines[0];
        assert_eq!(line.time_ms, 83450);
        assert_eq!(line.text, "哪怕只有");
        assert!(line.words.is_some());
        let words = line.words.as_ref().unwrap();
        assert_eq!(words.len(), 4);
        assert_eq!(words[0].text, "哪");
        assert_eq!(words[0].start_ms, 83450);
        assert_eq!(words[0].duration_ms, 300);
        assert_eq!(words[1].text, "怕");
        assert_eq!(words[1].start_ms, 83750);
        assert_eq!(words[1].duration_ms, 250);
        assert_eq!(words[3].text, "有");
        assert_eq!(words[3].start_ms, 84400);
        assert_eq!(words[3].duration_ms, 600);
    }

    #[test]
    fn test_parse_yrc_style() {
        let lrc = "[83450,3200](83450,300,0)哪(83750,250,0)怕";
        let parsed = Lyrics::parse_lrc(lrc);
        assert_eq!(parsed.lines.len(), 1);
        let line = &parsed.lines[0];
        assert_eq!(line.time_ms, 83450);
        assert_eq!(line.text, "哪怕");
        let words = line.words.as_ref().unwrap();
        assert_eq!(words.len(), 2);
        assert_eq!(words[0].text, "哪");
        assert_eq!(words[0].duration_ms, 300);
    }
}
