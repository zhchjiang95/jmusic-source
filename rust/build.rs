fn main() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if target_os == "android" {
        // Link libc++_shared dynamically. The Gradle build script will bundle
        // libc++_shared.so from the NDK into the APK's jniLibs.
        println!("cargo:rustc-link-lib=c++_shared");
    }
}
