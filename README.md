# 🎵 JMusic

一个使用 Flutter + Rust 构建的跨平台本地音乐播放器，支持在线歌词和专辑封面获取。

## ✨ 功能特性

- 🎶 **本地音乐播放** — 支持 MP3 / FLAC / WAV / OGG 等主流格式
- 📂 **目录扫描** — 选择音乐目录自动扫描并建立歌曲库（支持增量更新与自动清理已删除文件）
- 🔍 **在线匹配** — 自动从 QQ 音乐搜索匹配歌曲信息
- 📝 **歌词同步** — 在线获取 LRC 歌词，逐行高亮滚动
- 🖼️ **专辑封面** — 自动获取高清专辑封面
- 🔁 **播放模式** — 顺序播放 / 单曲循环 / 随机播放
- 🖥️ **全屏歌词** — 沉浸式歌词浏览，自动滚动居中

## 🏗️ 技术架构

| 层级 | 技术 | 说明 |
|------|------|------|
| **UI** | Flutter + Riverpod | Material 3 深色主题 |
| **桥接** | flutter_rust_bridge | Dart ↔ Rust FFI |
| **核心** | Rust | 音频解码、网络请求、文件扫描 |

### Rust 核心模块

```
rust/src/
├── api/          # FFI 接口（player、scanner、metadata）
├── audio/        # 音频播放引擎（rodio）
├── network/      # QQ 音乐 API 客户端（reqwest）
├── models/       # 数据模型（Song、Lyrics、Library）
└── storage/      # 本地持久化（JSON）
```

### Flutter UI 结构

```
lib/
├── main.dart             # 入口
├── pages/
│   ├── home_page.dart    # 歌曲库列表
│   └── player_page.dart  # 播放页 + 全屏歌词
├── widgets/
│   ├── mini_player.dart  # 底部迷你播放栏
│   └── lyrics_view.dart  # 歌词滚动组件
└── providers/
    └── app_providers.dart # Riverpod 状态管理
```

## 🚀 开始使用

### 环境要求

- Flutter SDK ≥ 3.11
- Rust toolchain（`rustup`）
- macOS: Xcode + CocoaPods

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
```

### 构建

```bash
flutter build macos
flutter build windows
flutter build linux
```

### 🖼️ 更新应用图标

如果需要更换或更新应用图标，请将新的正方形图标图片放置于根目录的 `assets/icon.png` 下，然后运行以下命令自动生成各平台图标：

```bash
flutter pub run flutter_launcher_icons
```
生成完毕后，如果你正在运行程序，需要停止 (`q`) 然后重新运行 `flutter run -d <platform>` 或构建才能看到新图标！

## 📄 License

MIT
