#[flutter_rust_bridge::frb(sync)] // Synchronous mode for simplicity of the demo
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}

/// 设置应用数据目录（Android 上需要从 Dart 端传入）
#[flutter_rust_bridge::frb(sync)]
pub fn set_app_data_dir(path: String) {
    crate::storage::set_data_dir(path);
}
