# Requirements Document

## Introduction

本特性在 macOS 端的系统菜单栏（NSStatusBar）新增一个状态栏项目，用于实时显示 JMusic 当前播放歌曲的歌词。该功能仅在 macOS 平台启用，与现有的 Windows 桌面悬浮歌词在交互方式上保持一致：均由 Flutter（Dart）侧的播放器状态驱动，通过 MethodChannel 推送数据到原生层（Swift/Cocoa），由原生层负责状态栏 UI 的渲染与交互。

主要价值：
- 用户在使用其他应用（窗口被遮挡或最小化）时，仍可通过菜单栏一目了然地看到当前歌词。
- 提供轻量的播放控制入口（点击状态栏项目弹出菜单，可执行播放/暂停、上一首、下一首、显示主窗口、关闭状态栏歌词等操作）。
- 通过用户偏好持久化开关状态，下次启动应用时自动恢复。

非目标（本期不做）：
- 不在 Windows / Linux / Android 平台启用本特性。
- 不实现“桌面悬浮歌词窗口”（macOS 桌面悬浮窗为另一独立特性，不在本需求范围内）。
- 不修改歌词解析、播放进度计算、在线歌词获取等已有逻辑。

## Glossary

- **Status_Bar_Lyrics**：在 macOS 菜单栏（NSStatusBar）展示当前播放歌词的状态栏项目。本文中作为系统名称。
- **Status_Bar_Item**：NSStatusBar 中由本特性创建的 NSStatusItem 实例。
- **Status_Bar_Menu**：点击 Status_Bar_Item 弹出的 NSMenu（包含播放控制与显示开关）。
- **Current_Line**：根据当前播放进度（毫秒）计算得到的当前歌词行文本（为最后一个 timeMs <= 当前进度 的行）。
- **Default_Title**：当不存在 Current_Line 时显示的默认占位文本，固定为 "JMusic"。
- **Lyrics_Update_Channel**：用于 Dart 与 macOS 原生层通信的 MethodChannel，名称为 `com.jmusic.app/macos_status_bar`。
- **Lyrics_Update_Interval**：Dart 侧定时器推送歌词更新的固定周期，为 500 毫秒（与现有 `_positionTimer` 周期一致）。
- **Max_Display_Length**：Status_Bar_Item 标题允许显示的最大字符长度，固定为 40 个字符（超过部分以 "…" 截断）。
- **Status_Bar_Lyrics_Enabled**：用户偏好项，布尔值，标识 Status_Bar_Lyrics 是否启用。持久化于应用偏好存储中（NSUserDefaults，键名 `status_bar_lyrics_enabled`）。
- **Player_State**：Dart 侧 Riverpod `playerProvider` 暴露的播放器状态，包含 `currentSong`、`lyrics`、`position`、`isPlaying`、`playMode` 等字段。
- **Show_Main_Window_Action**：从 Status_Bar_Menu 触发，用于将主窗口前置（`NSApp.activate(ignoringOtherApps: true)` 并 `makeKeyAndOrderFront`）的菜单项动作。

## Requirements

### Requirement 1: Status_Bar_Lyrics 在 macOS 平台的可用性

**User Story:** 作为 macOS 用户，我希望 JMusic 仅在 macOS 平台启用菜单栏歌词显示功能，以便其他平台不受影响。

#### Acceptance Criteria

1. WHERE 当前运行平台为 macOS，THE Status_Bar_Lyrics SHALL 在应用启动后初始化 Status_Bar_Item 并注册 Lyrics_Update_Channel。
2. WHERE 当前运行平台不是 macOS，THE Status_Bar_Lyrics SHALL 不创建 Status_Bar_Item，且 Dart 侧调用 Lyrics_Update_Channel 的方法时直接返回，不抛出异常。
3. THE Status_Bar_Lyrics SHALL 不修改任何已有的 `com.jmusic.app/tray`（Windows 托盘）或 `com.jmusic.app/player`（Android 媒体）通道的行为。

### Requirement 2: Status_Bar_Item 的初始化与显示

**User Story:** 作为用户，我希望应用启动后能在 macOS 菜单栏看到一个 JMusic 状态栏项目，以便随时查看歌词与控制播放。

#### Acceptance Criteria

1. WHEN 应用首次启动且 Status_Bar_Lyrics_Enabled 为 true，THE Status_Bar_Lyrics SHALL 在 NSStatusBar.system 中创建一个长度可变（NSStatusItem.variableLength）的 Status_Bar_Item。
2. WHEN Status_Bar_Item 被创建且不存在 Current_Line，THE Status_Bar_Lyrics SHALL 将 Status_Bar_Item 的标题设置为 Default_Title。
3. WHEN Status_Bar_Item 被创建，THE Status_Bar_Lyrics SHALL 为其绑定 Status_Bar_Menu。
4. WHEN 应用首次启动且 Status_Bar_Lyrics_Enabled 为 false，THE Status_Bar_Lyrics SHALL 不创建 Status_Bar_Item。
5. IF Status_Bar_Item 创建失败，THEN THE Status_Bar_Lyrics SHALL 在 macOS 控制台输出一条错误日志（前缀 `[StatusBarLyrics]`）并不再重试本次启动的初始化。

### Requirement 3: 实时歌词推送与显示

**User Story:** 作为用户，我希望菜单栏歌词随播放进度实时更新到当前行，以便准确跟随当前演唱内容。

#### Acceptance Criteria

1. WHILE 应用处于运行状态且 Status_Bar_Lyrics_Enabled 为 true，THE Player_State 的 Dart 侧定时器 SHALL 以 Lyrics_Update_Interval（500ms）为周期通过 Lyrics_Update_Channel 调用 `updateLyrics` 方法，推送当前的 Current_Line 文本。
2. WHEN Lyrics_Update_Channel 接收到 `updateLyrics` 调用且新的 Current_Line 文本与 Status_Bar_Item 当前标题不一致，THE Status_Bar_Lyrics SHALL 在主线程更新 Status_Bar_Item 的标题为新的 Current_Line。
3. WHEN Lyrics_Update_Channel 接收到 `updateLyrics` 调用且新的 Current_Line 文本与 Status_Bar_Item 当前标题一致，THE Status_Bar_Lyrics SHALL 不重新设置 Status_Bar_Item 的标题（避免无意义的 UI 重绘）。
4. WHEN 计算得到的 Current_Line 文本（按 Unicode 字符计）长度大于 Max_Display_Length，THE Status_Bar_Lyrics SHALL 截取前 Max_Display_Length 个字符并在末尾追加 "…" 后再设置为 Status_Bar_Item 的标题。
5. WHEN Player_State 的 `lyrics` 为空或 `lyrics.lines` 为空数组，THE Status_Bar_Lyrics SHALL 将 Status_Bar_Item 的标题设置为 Default_Title。
6. WHEN Player_State 的 `currentSong` 不为空但当前播放进度小于第一行歌词的 timeMs，THE Status_Bar_Lyrics SHALL 将 Status_Bar_Item 的标题设置为 `{歌曲标题} - {艺术家}` 格式（同样受 Max_Display_Length 限制）。
7. WHEN Player_State 的 `currentSong` 为空，THE Status_Bar_Lyrics SHALL 将 Status_Bar_Item 的标题设置为 Default_Title。
8. WHEN 用户切换歌曲（`currentSong.filePath` 发生变化），THE Status_Bar_Lyrics SHALL 在切换瞬间将 Status_Bar_Item 的标题立即更新为新歌曲的 `{歌曲标题} - {艺术家}` 格式，无需等待下一个 Lyrics_Update_Interval。

### Requirement 4: Status_Bar_Menu 的播放控制

**User Story:** 作为用户，我希望点击菜单栏歌词项目能展开菜单进行播放控制，以便不切回主窗口也能操作。

#### Acceptance Criteria

1. WHEN 用户左键点击 Status_Bar_Item，THE Status_Bar_Lyrics SHALL 弹出 Status_Bar_Menu。
2. THE Status_Bar_Menu SHALL 包含以下菜单项，按从上到下的顺序排列：
   1. 当前歌曲信息（不可点击的标题项，显示 `{歌曲标题} - {艺术家}`，无歌曲时显示 "未在播放"）
   2. 分隔符
   3. "播放 / 暂停"
   4. "上一首"
   5. "下一首"
   6. 分隔符
   7. "显示主窗口"
   8. 分隔符
   9. "关闭状态栏歌词"
3. WHEN 用户点击 "播放 / 暂停" 菜单项，THE Status_Bar_Lyrics SHALL 通过 Lyrics_Update_Channel 向 Dart 侧发送 `togglePlayPause` 事件。
4. WHEN 用户点击 "上一首" 菜单项，THE Status_Bar_Lyrics SHALL 通过 Lyrics_Update_Channel 向 Dart 侧发送 `previous` 事件。
5. WHEN 用户点击 "下一首" 菜单项，THE Status_Bar_Lyrics SHALL 通过 Lyrics_Update_Channel 向 Dart 侧发送 `next` 事件。
6. WHEN 用户点击 "显示主窗口" 菜单项，THE Status_Bar_Lyrics SHALL 在原生层执行 Show_Main_Window_Action。
7. WHEN 用户点击 "关闭状态栏歌词" 菜单项，THE Status_Bar_Lyrics SHALL 将 Status_Bar_Lyrics_Enabled 设置为 false、从 NSStatusBar 中移除 Status_Bar_Item，并通过 Lyrics_Update_Channel 通知 Dart 侧停止推送歌词更新。
8. WHEN Dart 侧接收到 `togglePlayPause` / `previous` / `next` 事件，THE Player_State 的对应方法（`togglePlayPause` / `previous` / `next`）SHALL 被调用一次。

### Requirement 5: 通过设置项启用与关闭 Status_Bar_Lyrics

**User Story:** 作为用户，我希望能在应用内随时启用或关闭菜单栏歌词功能，以便按需使用。

#### Acceptance Criteria

1. WHERE 当前运行平台为 macOS，THE 应用设置界面 SHALL 提供一个名为 "在菜单栏显示歌词" 的开关控件，控件状态绑定到 Status_Bar_Lyrics_Enabled。
2. WHEN 用户将 "在菜单栏显示歌词" 开关从关闭切换为开启，THE Status_Bar_Lyrics SHALL 立即创建 Status_Bar_Item（若尚未存在）、按 Requirement 3 计算并显示当前歌词、并将 Status_Bar_Lyrics_Enabled 持久化为 true。
3. WHEN 用户将 "在菜单栏显示歌词" 开关从开启切换为关闭，THE Status_Bar_Lyrics SHALL 立即从 NSStatusBar 中移除 Status_Bar_Item、停止 Dart 侧的歌词推送，并将 Status_Bar_Lyrics_Enabled 持久化为 false。
4. WHEN 应用启动且 Status_Bar_Lyrics_Enabled 在持久化存储中不存在，THE Status_Bar_Lyrics SHALL 将其默认值视为 true。
5. WHEN 用户通过 Status_Bar_Menu 的 "关闭状态栏歌词" 菜单项关闭功能，THE 应用设置界面的 "在菜单栏显示歌词" 开关 SHALL 在下次显示时反映为关闭状态。

### Requirement 6: 错误处理与稳定性

**User Story:** 作为用户，我希望状态栏歌词功能在异常情况下不影响主程序，以便专注于音乐播放本身。

#### Acceptance Criteria

1. IF Lyrics_Update_Channel 在 Dart 侧调用时抛出异常（例如插件未注册），THEN THE Player_State 的更新流程 SHALL 捕获该异常并继续执行后续逻辑（不中断 `_positionTimer`、不影响播放进度、不影响主窗口的歌词显示）。
2. IF 原生层在处理 `updateLyrics` / `togglePlayPause` / `previous` / `next` 调用时发生异常，THEN THE Status_Bar_Lyrics SHALL 捕获该异常并在 macOS 控制台输出一条错误日志（前缀 `[StatusBarLyrics]`），不向 Dart 侧抛出致命错误。
3. WHEN 应用即将退出（`applicationWillTerminate`），THE Status_Bar_Lyrics SHALL 主动从 NSStatusBar 中移除 Status_Bar_Item，避免菜单栏残留。
4. WHILE Status_Bar_Lyrics_Enabled 为 false，THE Player_State 的 Dart 侧定时器 SHALL 不通过 Lyrics_Update_Channel 推送 `updateLyrics` 调用（避免无意义的跨语言调用开销）。

### Requirement 7: 与现有特性的兼容性

**User Story:** 作为开发者，我希望本特性的代码组织清晰，不破坏既有的 Windows / Android 平台行为，以便未来维护。

#### Acceptance Criteria

1. THE Status_Bar_Lyrics 相关的 Dart 代码 SHALL 集中在新文件 `lib/providers/macos_status_bar.dart`（或同名命名空间内的工具类）中，不与现有的 `NativeUtils.updateLyricsOverlay`（Windows 桌面悬浮歌词）方法混用。
2. THE Status_Bar_Lyrics 相关的原生代码 SHALL 集中在新文件 `macos/Runner/StatusBarLyricsController.swift` 中，由 `MainFlutterWindow.swift` 或 `AppDelegate.swift` 在应用启动时初始化一次。
3. WHEN Status_Bar_Lyrics_Enabled 为 true 时 Dart 侧推送歌词更新，THE 调用 SHALL 通过新的 Lyrics_Update_Channel（`com.jmusic.app/macos_status_bar`）发送，不复用 `com.jmusic.app/tray` 通道。
4. THE Player_State 的现有字段（`currentSong`、`lyrics`、`position`、`isPlaying`、`playMode`、`playlist`）SHALL 不因本特性而修改其结构或类型。
