use std::fs;
use std::path::PathBuf;

use crate::models::song::Library;

/// 获取应用数据目录
fn get_data_dir() -> PathBuf {
    let home = dirs_path();
    let data_dir = home.join(".jmusic");
    fs::create_dir_all(&data_dir).ok();
    data_dir
}

/// 获取用户主目录
fn dirs_path() -> PathBuf {
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
        PathBuf::from("/data/local/tmp")
    }
    #[cfg(target_os = "ios")]
    {
        PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string()))
    }
}

/// 获取歌曲库 JSON 文件路径
fn library_path() -> PathBuf {
    get_data_dir().join("library.json")
}

/// 读取歌曲库
pub fn load_library() -> Library {
    let path = library_path();
    if path.exists() {
        match fs::read_to_string(&path) {
            Ok(content) => serde_json::from_str(&content).unwrap_or_else(|_| Library::new()),
            Err(_) => Library::new(),
        }
    } else {
        Library::new()
    }
}

/// 保存歌曲库到 JSON 文件
pub fn save_library(library: &Library) -> Result<(), String> {
    let path = library_path();
    let json = serde_json::to_string_pretty(library)
        .map_err(|e| format!("序列化歌曲库失败: {}", e))?;
    fs::write(&path, json).map_err(|e| format!("写入歌曲库文件失败: {}", e))?;
    Ok(())
}
