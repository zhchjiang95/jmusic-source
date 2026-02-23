use serde::{Deserialize, Serialize};

/// 单行歌词
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LyricLine {
    /// 时间戳（毫秒）
    pub time_ms: u64,
    /// 歌词文本
    pub text: String,
}

/// 歌词数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Lyrics {
    /// 歌词行列表（按时间排序）
    pub lines: Vec<LyricLine>,
}

impl Lyrics {
    /// 从 LRC 格式文本解析歌词
    pub fn parse_lrc(lrc_text: &str) -> Self {
        let mut lines = Vec::new();

        for line in lrc_text.lines() {
            // 匹配 [mm:ss.xx] 格式
            let line = line.trim();
            if line.is_empty() {
                continue;
            }

            // 提取所有时间标签和歌词文本
            let mut text_start = 0;
            let mut timestamps = Vec::new();

            let chars: Vec<char> = line.chars().collect();
            let mut i = 0;

            while i < chars.len() {
                if chars[i] == '[' {
                    // 查找匹配的 ]
                    if let Some(end) = chars[i + 1..].iter().position(|&c| c == ']') {
                        let tag_content: String = chars[i + 1..i + 1 + end].iter().collect();
                        // 尝试解析时间标签
                        if let Some(ms) = Self::parse_time_tag(&tag_content) {
                            timestamps.push(ms);
                        }
                        i = i + 1 + end + 1;
                        text_start = i;
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            }

            // 获取歌词文本
            let text: String = chars[text_start..].iter().collect();
            let text = text.trim().to_string();

            if text.is_empty() {
                continue;
            }

            // 为每个时间标签创建一行歌词
            for ms in timestamps {
                lines.push(LyricLine {
                    time_ms: ms,
                    text: text.clone(),
                });
            }
        }

        // 按时间排序
        lines.sort_by_key(|l| l.time_ms);

        Lyrics { lines }
    }

    /// 解析时间标签 "mm:ss.xx" 或 "mm:ss.xxx" 为毫秒
    fn parse_time_tag(tag: &str) -> Option<u64> {
        let parts: Vec<&str> = tag.split(':').collect();
        if parts.len() != 2 {
            return None;
        }

        let minutes: u64 = parts[0].parse().ok()?;
        let sec_parts: Vec<&str> = parts[1].split('.').collect();
        if sec_parts.is_empty() {
            return None;
        }

        let seconds: u64 = sec_parts[0].parse().ok()?;
        let millis = if sec_parts.len() > 1 {
            let ms_str = sec_parts[1];
            let ms: u64 = ms_str.parse().ok()?;
            // 如果只有两位数字，转换为毫秒（如 "25" → 250）
            if ms_str.len() == 2 {
                ms * 10
            } else {
                ms
            }
        } else {
            0
        };

        Some(minutes * 60 * 1000 + seconds * 1000 + millis)
    }
}
