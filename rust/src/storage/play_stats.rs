use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

/// 播放统计数据结构
#[derive(Serialize, Deserialize, Default)]
struct PlayStatsData {
    /// file_path -> (title, artist, count)
    entries: HashMap<String, PlayStatsEntry>,
}

#[derive(Serialize, Deserialize, Clone)]
struct PlayStatsEntry {
    title: String,
    artist: String,
    count: u32,
}

/// 获取播放统计文件路径
fn stats_path() -> PathBuf {
    let home_dir = {
        #[cfg(any(target_os = "macos", target_os = "linux", target_os = "ios"))]
        {
            PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string()))
        }
        #[cfg(target_os = "windows")]
        {
            PathBuf::from(
                std::env::var("USERPROFILE")
                    .unwrap_or_else(|_| "C:\\".to_string()),
            )
        }
        #[cfg(target_os = "android")]
        {
            PathBuf::from("/data/local/tmp")
        }
    };

    let data_dir = home_dir.join(".jmusic");
    fs::create_dir_all(&data_dir).ok();
    data_dir.join("play_stats.json")
}

/// 加载播放统计数据
fn load_stats_data() -> PlayStatsData {
    let path = stats_path();
    if path.exists() {
        match fs::read_to_string(&path) {
            Ok(content) => serde_json::from_str(&content).unwrap_or_default(),
            Err(_) => PlayStatsData::default(),
        }
    } else {
        PlayStatsData::default()
    }
}

/// 保存播放统计数据
fn save_stats_data(data: &PlayStatsData) {
    let path = stats_path();
    if let Ok(json) = serde_json::to_string_pretty(data) {
        fs::write(&path, json).ok();
    }
}

/// 增加播放次数
pub fn increment_play_count(file_path: &str, title: &str, artist: &str) {
    let mut data = load_stats_data();
    let entry = data.entries.entry(file_path.to_string()).or_insert(PlayStatsEntry {
        title: title.to_string(),
        artist: artist.to_string(),
        count: 0,
    });
    entry.count += 1;
    // 更新标题和歌手（可能被编辑过）
    entry.title = title.to_string();
    entry.artist = artist.to_string();
    save_stats_data(&data);
}

/// 获取指定歌曲的播放次数
pub fn get_play_count(file_path: &str) -> u32 {
    let data = load_stats_data();
    data.entries.get(file_path).map(|e| e.count).unwrap_or(0)
}

/// 加载所有播放统计（返回 file_path -> (title, artist, count)）
pub fn load_play_stats() -> HashMap<String, (String, String, u32)> {
    let data = load_stats_data();
    data.entries
        .into_iter()
        .map(|(k, v)| (k, (v.title, v.artist, v.count)))
        .collect()
}
