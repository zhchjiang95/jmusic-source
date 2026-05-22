plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.jmusic.jmusic"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.jmusic.jmusic"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Bundle libc++_shared.so from NDK for each ABI
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.media:media:1.7.0")
}

// Task to copy libc++_shared.so from NDK into jniLibs before merging native libs
tasks.register("copyLibCppShared") {
    doLast {
        val ndkDir = android.ndkDirectory
        val hostTag = if (org.apache.tools.ant.taskdefs.condition.Os.isFamily(org.apache.tools.ant.taskdefs.condition.Os.FAMILY_WINDOWS)) {
            "windows-x86_64"
        } else if (org.apache.tools.ant.taskdefs.condition.Os.isFamily(org.apache.tools.ant.taskdefs.condition.Os.FAMILY_MAC)) {
            "darwin-x86_64"
        } else {
            "linux-x86_64"
        }
        val sysrootLib = File(ndkDir, "toolchains/llvm/prebuilt/$hostTag/sysroot/usr/lib")
        val jniLibsDir = File(projectDir, "src/main/jniLibs")

        val abiMap = mapOf(
            "arm64-v8a" to "aarch64-linux-android",
            "armeabi-v7a" to "arm-linux-androideabi",
            "x86_64" to "x86_64-linux-android"
        )

        abiMap.forEach { (abi, triple) ->
            val src = File(sysrootLib, "$triple/libc++_shared.so")
            if (src.exists()) {
                val dstDir = File(jniLibsDir, abi)
                dstDir.mkdirs()
                val dst = File(dstDir, "libc++_shared.so")
                src.copyTo(dst, overwrite = true)
                println("Copied libc++_shared.so for $abi")
            } else {
                println("WARNING: libc++_shared.so not found at $src")
            }
        }
    }
}

tasks.matching { it.name.contains("mergeReleaseNativeLibs") || it.name.contains("mergeDebugNativeLibs") }.configureEach {
    dependsOn("copyLibCppShared")
}
