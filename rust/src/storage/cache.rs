use std::fs;
use std::path::PathBuf;

/// 获取缓存目录
fn cache_dir() -> PathBuf {
    let home = super::library::load_library(); // 仅用来触发 data_dir 创建
    drop(home);

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

    let dir = home_dir.join(".jmusic").join("cache");
    fs::create_dir_all(&dir).ok();
    dir
}

/// 获取歌词缓存目录
fn lyrics_cache_dir() -> PathBuf {
    let dir = cache_dir().join("lyrics");
    fs::create_dir_all(&dir).ok();
    dir
}

/// 获取封面缓存目录
fn covers_cache_dir() -> PathBuf {
    let dir = cache_dir().join("covers");
    fs::create_dir_all(&dir).ok();
    dir
}

/// 读取缓存的歌词（LRC 格式文本）
pub fn load_cached_lyrics(songmid: &str) -> Option<String> {
    let path = lyrics_cache_dir().join(format!("{}.lrc", songmid));
    fs::read_to_string(path).ok()
}

/// 保存歌词到缓存
pub fn save_lyrics_cache(songmid: &str, lrc_text: &str) -> Result<(), String> {
    let path = lyrics_cache_dir().join(format!("{}.lrc", songmid));
    fs::write(&path, lrc_text).map_err(|e| format!("保存歌词缓存失败: {}", e))
}

/// 读取缓存的封面图片
pub fn load_cached_cover(albummid: &str) -> Option<Vec<u8>> {
    let path = covers_cache_dir().join(format!("{}.jpg", albummid));
    fs::read(path).ok()
}

/// 保存封面图片到缓存
pub fn save_cover_cache(albummid: &str, data: &[u8]) -> Result<(), String> {
    let path = covers_cache_dir().join(format!("{}.jpg", albummid));
    fs::write(&path, data).map_err(|e| format!("保存封面缓存失败: {}", e))
}

/// 获取缓存的封面文件路径（如果存在）
pub fn get_cover_cache_path(albummid: &str) -> Option<String> {
    let path = covers_cache_dir().join(format!("{}.jpg", albummid));
    if path.exists() {
        path.to_str().map(|s| s.to_string())
    } else {
        None
    }
}
