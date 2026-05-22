pub mod library;
pub mod cache;
pub mod play_stats;

use std::path::PathBuf;
use std::sync::OnceLock;

/// 全局应用数据目录（Android 上由 Dart 端设置）
static APP_DATA_DIR: OnceLock<PathBuf> = OnceLock::new();

/// 设置应用数据目录
pub fn set_data_dir(path: String) {
    let _ = APP_DATA_DIR.set(PathBuf::from(path));
}

/// 获取应用数据目录
pub fn get_app_data_dir() -> PathBuf {
    if let Some(dir) = APP_DATA_DIR.get() {
        return dir.clone();
    }

    // Fallback: 各平台默认路径
    let home = {
        #[cfg(target_os = "macos")]
        {
            PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string()))
        }
        #[cfg(target_os = "windows")]
        {
            PathBuf::from(
                std::env::var("USERPROFILE")
                    .unwrap_or_else(|_| std::env::var("HOMEPATH").unwrap_or_else(|_| "C:\\".to_string())),
            )
        }
        #[cfg(target_os = "linux")]
        {
            PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string()))
        }
        #[cfg(target_os = "android")]
        {
            // This shouldn't be reached if set_data_dir was called properly
            PathBuf::from("/data/local/tmp")
        }
        #[cfg(target_os = "ios")]
        {
            PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string()))
        }
    };

    home.join(".jmusic")
}
