# 🎵 JMusic

一个使用 Flutter + Rust 构建的跨平台本地音乐播放器，支持在线歌词和专辑封面获取。

## ✨ 功能特性

- 🎶 **本地音乐播放** — 支持 MP3 / FLAC / WAV / OGG 等主流格式
- 📂 **目录扫描** — 选择音乐目录自动扫描并建立歌曲库
- 🔍 **在线匹配** — ~~自动从 QQ 音乐搜索匹配歌曲信息~~（可能失效，使用手动编辑并写入到源文件）
- 📝 **歌词同步** — ~~在线获取 LRC 歌词，逐行高亮滚动~~（可能失效，使用手动导入歌词并写入到源文件）
- 🖼️ **专辑封面** — ~~自动获取高清专辑封面~~（可能失效，使用手动导入专辑封面并写入到源文件）
- 🔁 **播放模式** — 顺序播放 / 单曲循环 / 随机播放
- 🖥️ **全屏歌词** — 沉浸式歌词浏览，支持长歌词自动换行左对齐并平滑滚动居中
- 🎤 **桌面悬浮歌词**（Windows）— 透明置顶窗口实时显示当前歌词+下一行，支持拖拽定位、字号调节、鼠标穿透锁定
- 🍎 **菜单栏歌词**（macOS）— 系统状态栏实时显示当前歌词，可通过状态栏菜单完成播放/暂停、上一首、下一首、显示主窗口、关闭等操作；关闭主窗口仅隐藏，应用继续在后台运行
- 📊 **音频可视化频谱** — 实时 FFT 频谱分析（Rust 端 2048 点 realfft + 64 对数分箱），支持柱状和环形两种可视化样式，60 FPS 平滑动画，同时展示在播放页和全屏歌词页
- 🎨 **动态主题色** — 自动从专辑封面提取主色调，整个 UI 配色（按钮、进度条、频谱、渐变背景）跟随当前歌曲动态切换，Material You 风格
- 🃏 **歌词卡片分享** — 全屏歌词页长按任意歌词行，生成精美分享卡片（封面模糊背景 + 歌词 + 歌曲信息 + 官网二维码），可导出为高清 PNG 图片

## 📸 应用截图

> 截图存放于项目根目录的 `screenshots/` 文件夹下。如需更新，替换对应文件即可。

### 主界面

|              主页 / 歌曲库              |             播放页 / 歌词              |
| :-------------------------------------: | :------------------------------------: |
| ![主页](screenshots/home.png) | ![播放页](screenshots/player.png) |

### 沉浸式与桌面歌词

|             全屏歌词              |            桌面悬浮歌词（Windows）             |
| :-------------------------------: | :--------------------------------------------: |
| ![全屏歌词](screenshots/fullscreen-lyrics.png) | ![桌面歌词](screenshots/desktop-lyrics.png) |

### macOS 菜单栏歌词

<p align="center">
  <img src="screenshots/menubar-lyrics.png" alt="macOS 菜单栏歌词" width="600" />
</p>

## 🏗️ 技术架构

| 层级     | 技术                | 说明                              |
| -------- | ------------------- | --------------------------------- |
| **UI**   | Flutter + Riverpod  | Material 3 动态主题（封面色提取） |
| **桥接** | flutter_rust_bridge | Dart ↔ Rust FFI                   |
| **核心** | Rust                | 音频解码、频谱分析、网络请求、文件扫描 |

### Rust 核心模块

```
rust/src/
├── api/          # FFI 接口（player、scanner、metadata）
├── audio/        # 音频播放引擎（rodio）+ 频谱分析（realfft）
├── network/      # QQ 音乐 API 客户端（reqwest）
├── models/       # 数据模型（Song、Lyrics、Library）
└── storage/      # 本地持久化（JSON）
```

### Flutter UI 结构

```
lib/
├── main.dart             # 入口（动态主题）
├── pages/
│   ├── home_page.dart    # 歌曲库列表
│   └── player_page.dart  # 播放页 + 全屏歌词
├── widgets/
│   ├── mini_player.dart  # 底部迷你播放栏
│   ├── lyrics_view.dart  # 歌词滚动组件（支持长按分享）
│   ├── lyrics_card.dart  # 歌词卡片生成与导出
│   └── spectrum_view.dart # 频谱可视化组件（柱状/环形）
└── providers/
    ├── app_providers.dart      # Riverpod 状态管理
    ├── spectrum.dart           # 频谱样式枚举与常量
    ├── dynamic_theme.dart      # 封面色提取动态主题
    └── macos_status_bar.dart   # macOS 菜单栏歌词控制器
```

### macOS 原生模块

```
macos/Runner/
├── AppDelegate.swift                  # 启动注册 / 关闭按钮策略 / Dock 重新激活 / 退出清理
├── MainFlutterWindow.swift            # 在 awakeFromNib 中 attach 状态栏歌词控制器
├── MainWindowDelegate.swift           # windowShouldClose 拦截：关闭=隐藏不退出
└── StatusBarLyricsController.swift    # NSStatusItem + NSMenu + setText 去重
```

菜单栏歌词的 Dart 端通过 `MethodChannel('com.jmusic.app/macos_status_bar')` 与 Swift 端通信：Dart 推送 `setEnabled / setText / showMainWindow / dispose`，Swift 端把菜单点击通过 `onMenuAction` 回送给 Dart。偏好以 Dart 端 `SharedPreferences` 为唯一来源，键为 `status_bar_lyrics_enabled`，默认启用。

## 📦 下载与安装 (macOS)

您可以直接从 GitHub Releases 下载已打包好的 Mac 版本：

1. 下载 `JMusic-mac.zip` 并解压得到应用文件。
2. **⚠️ 兼容性注意**：当前发布的版本**仅兼容搭载 Apple Silicon (M1/M2/M3等 M系列芯片)** 的 Mac，暂不支持 Intel 芯片的 Mac 电脑。
3. **遇到“应用已损坏”或“无法验证开发者”怎么办？**
   由于应用未经过 Apple 开发者签名公证，首次打开时会被 macOS 拦截。请打开**终端 (Terminal)**，执行以下命令移除安全隔离属性：
   ```bash
   xattr -cr /你的解压路径/你的应用名称.app
   ```
   _(小提示：你可以先输入 `xattr -cr ` —— 注意结尾有个空格，然后把解压出来的 app 文件直接拖进终端窗口，再按回车键即可)_

## 🛠️ 本地开发与构建

### 环境要求

- Flutter SDK ≥ 3.11
- Rust toolchain（`rustup`）
- macOS: Xcode + CocoaPods
- Android:
  - **Android SDK** 和 **JDK 17** (通常通过安装 Android Studio 自动配置)
  - **Android NDK** (需要在 Android Studio 的 SDK Manager -> SDK Tools 中勾选 `NDK (Side by side)` 进行安装)
  - **Rust Android 跨平台编译目标**:
    ```bash
    rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android
    ```

### 运行

```bash
# 安装依赖
flutter pub get

# macOS
cd macos && pod install && cd ..
flutter run -d macos

# 其他平台
flutter run -d windows
flutter run -d linux
flutter run -d <android-device-id> # 运行到安卓设备或模拟器
```

### 构建

```bash
flutter build macos
flutter build windows
flutter build linux
flutter build apk         # 构建 Android APK 包
flutter build appbundle   # 构建 Google Play 的 AAB 格式包
# 清缓存构建 Android APK 包
flutter clean
flutter_rust_bridge_codegen generate
flutter build apk
```

### 🖼️ 更新应用图标

如果需要更换或更新应用图标，请将新的正方形图标图片放置于根目录的 `assets/icon.png` 下，然后运行以下命令自动生成各平台图标：

```bash
flutter pub run flutter_launcher_icons
```

生成完毕后，如果你正在运行程序，需要停止 (`q`) 然后重新运行 `flutter run -d <platform>` 或构建才能看到新图标！

## 📄 License

MIT
