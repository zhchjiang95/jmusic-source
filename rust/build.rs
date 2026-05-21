fn main() {
    // On Android, explicitly link against libc++ to resolve C++ runtime symbols
    // like __cxa_pure_virtual that some dependencies require.
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if target_os == "android" {
        println!("cargo:rustc-link-lib=c++_shared");
    }
}
