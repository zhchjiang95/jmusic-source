use crate::storage;

/// 清除所有缓存（歌词 + 封面）
#[flutter_rust_bridge::frb]
pub fn clear_all_cache() -> Result<(), String> {
    let home_dir = {
        #[cfg(any(target_os = "macos", target_os = "linux", target_os = "ios"))]
        {
            std::path::PathBuf::from(
                std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string()),
            )
        }
        #[cfg(target_os = "windows")]
        {
            std::path::PathBuf::from(
                std::env::var("USERPROFILE").unwrap_or_else(|_| "C:\\".to_string()),
            )
        }
        #[cfg(target_os = "android")]
        {
            std::path::PathBuf::from("/data/local/tmp")
        }
    };

    let cache_dir = home_dir.join(".jmusic").join("cache");
    if cache_dir.exists() {
        std::fs::remove_dir_all(&cache_dir)
            .map_err(|e| format!("清除缓存目录失败: {}", e))?;
    }
    Ok(())
}

/// 重置歌曲库（清空所有数据）
#[flutter_rust_bridge::frb]
pub fn reset_library() -> Result<(), String> {
    let library = crate::models::song::Library::new();
    storage::library::save_library(&library)
}
