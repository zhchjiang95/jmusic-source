use crate::storage::play_stats as stats_storage;

/// 播放次数记录项
#[flutter_rust_bridge::frb]
#[derive(Clone)]
pub struct PlayCountEntry {
    pub file_path: String,
    pub title: String,
    pub artist: String,
    pub count: u32,
}

/// 记录一次播放（增加播放次数）
#[flutter_rust_bridge::frb(sync)]
pub fn record_play(file_path: String, title: String, artist: String) {
    stats_storage::increment_play_count(&file_path, &title, &artist);
}

/// 获取播放次数排行榜（按播放次数降序）
#[flutter_rust_bridge::frb(sync)]
pub fn get_play_stats() -> Vec<PlayCountEntry> {
    let data = stats_storage::load_play_stats();
    let mut entries: Vec<PlayCountEntry> = data
        .into_iter()
        .map(|(file_path, (title, artist, count))| PlayCountEntry {
            file_path,
            title,
            artist,
            count,
        })
        .collect();
    entries.sort_by(|a, b| b.count.cmp(&a.count));
    entries
}

/// 获取指定歌曲的播放次数
#[flutter_rust_bridge::frb(sync)]
pub fn get_play_count(file_path: String) -> u32 {
    stats_storage::get_play_count(&file_path)
}
