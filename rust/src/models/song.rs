use serde::{Deserialize, Serialize};

/// 歌曲信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Song {
    /// 本地文件路径
    pub file_path: String,
    /// 歌曲标题
    pub title: String,
    /// 歌手
    pub artist: String,
    /// 专辑名
    pub album: String,
    /// 时长（秒）
    pub duration: f64,
    /// 文件大小（字节）
    pub file_size: u64,
    /// 文件格式（mp3/flac/wav 等）
    pub format: String,
    /// QQ 音乐 songmid（在线匹配后填充）
    pub songmid: Option<String>,
    /// QQ 音乐 albummid（在线匹配后填充）
    pub albummid: Option<String>,
    /// 文件最后修改时间戳
    pub modified_at: u64,
}

/// 歌曲库（本地 JSON 持久化的根结构）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Library {
    /// 歌曲列表
    pub songs: Vec<Song>,
    /// 扫描的目录列表
    pub scan_dirs: Vec<String>,
    /// 上次扫描时间戳
    pub last_scan_at: u64,
}

impl Library {
    /// 创建空的歌曲库
    pub fn new() -> Self {
        Self {
            songs: Vec::new(),
            scan_dirs: Vec::new(),
            last_scan_at: 0,
        }
    }
}

impl Default for Library {
    fn default() -> Self {
        Self::new()
    }
}

/// QQ 音乐搜索结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QQMusicSearchResult {
    pub songmid: String,
    pub songname: String,
    pub albummid: String,
    pub albumname: String,
    pub singer: Vec<Singer>,
    pub interval: u64,
}

/// 歌手信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Singer {
    pub id: u64,
    pub mid: String,
    pub name: String,
}
