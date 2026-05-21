use crate::storage;

/// 重置歌曲库（清空所有数据）
#[flutter_rust_bridge::frb]
pub fn reset_library() -> Result<(), String> {
    let library = crate::models::song::Library::new();
    storage::library::save_library(&library)
}
