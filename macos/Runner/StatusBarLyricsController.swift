import Cocoa
import FlutterMacOS

/// 菜单栏歌词控制器（Wave 1：Task 7 基础部分；菜单构建在 Task 8 中实现）。
///
/// 职责：
///   - 持有 `NSStatusItem` 与对应的 `NSMenu`
///   - 注册 MethodChannel `com.jmusic.app/macos_status_bar` 并响应 Dart 侧
///     的 `setEnabled / setText / showMainWindow / dispose` 调用
///   - 在 Task 8 中接入菜单回调，把用户操作通过 `invokeMethod("onMenuAction", …)`
///     回送给 Dart 侧
///
/// 与 Windows tray (`com.jmusic.app/tray`) 完全隔离：通道名、handler、
/// NSStatusItem 都独立维护，禁止共用。
final class StatusBarLyricsController: NSObject {

  // MARK: - 常量

  private static let channelName = "com.jmusic.app/macos_status_bar"
  private static let defaultTitle = "JMusic"
  private static let logPrefix = "[StatusBarLyrics]"

  // MARK: - 字段

  private let channel: FlutterMethodChannel

  /// 当前的 NSStatusItem。`nil` 表示未启用或创建失败。
  /// 仅在主线程上访问。
  private var statusItem: NSStatusItem?

  /// 由 `buildMenu()` 构建（Task 8 实现）。
  /// 在 `setEnabled(true)` 时绑定到 `statusItem.menu`。
  private var menu: NSMenu?

  /// 菜单第一项（不可点击的当前歌曲信息标题项）。
  /// 文本随 `setText` 同步刷新。
  private weak var menuTitleItem: NSMenuItem?

  /// 当前是否启用。由 Dart 侧通过 `setEnabled` 同步。
  private var enabled: Bool = false

  /// 用于在 NSStatusItem 创建失败后跳过本次启动的重试（R2.5）。
  private var hasFailedToCreateStatusItem: Bool = false

  // MARK: - 初始化

  init(messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(
      name: StatusBarLyricsController.channelName,
      binaryMessenger: messenger
    )
    super.init()
    self.channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  // MARK: - MethodChannel handler

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "setEnabled":
        let value = (call.arguments as? Bool) ?? false
        try self.setEnabled(value)
        result(nil)
      case "setText":
        let text = (call.arguments as? String) ?? StatusBarLyricsController.defaultTitle
        self.setText(text)
        result(nil)
      case "showMainWindow":
        self.showMainWindow()
        result(nil)
      case "dispose":
        self.tearDown()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      NSLog("\(StatusBarLyricsController.logPrefix) handler error for \(call.method): \(error)")
      // 不向 Dart 抛 FlutterError；Dart 侧已包 try/catch，但保险起见返回 nil
      result(nil)
    }
  }

  // MARK: - 公共生命周期 API（供 AppDelegate 调用）

  /// 应用即将退出时调用：移除 NSStatusItem，避免菜单栏残留（R6.3）。
  func tearDown() {
    DispatchQueue.main.async {
      if let item = self.statusItem {
        NSStatusBar.system.removeStatusItem(item)
        self.statusItem = nil
      }
      self.menu = nil
      self.menuTitleItem = nil
      self.enabled = false
    }
  }

  // MARK: - 私有：启用/禁用

  private func setEnabled(_ on: Bool) throws {
    DispatchQueue.main.async {
      self.enabled = on
      if on {
        self.createStatusItemIfNeeded()
      } else {
        if let item = self.statusItem {
          NSStatusBar.system.removeStatusItem(item)
          self.statusItem = nil
        }
        self.menu = nil
        self.menuTitleItem = nil
      }
    }
  }

  private func createStatusItemIfNeeded() {
    guard self.statusItem == nil else { return }
    guard !self.hasFailedToCreateStatusItem else { return }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    // 仅设置 title，不设置 image（用户需求：只显示一行文字，无图标前缀）
    item.button?.title = StatusBarLyricsController.defaultTitle
    // 不设置 button.action / target：依赖 NSStatusItem 默认菜单展开行为
    item.menu = self.buildMenu()
    self.statusItem = item

    if item.button == nil {
      // 按 R2.5：本次启动不重试，记一次日志
      NSLog("\(StatusBarLyricsController.logPrefix) failed to create status item: button is nil")
      NSStatusBar.system.removeStatusItem(item)
      self.statusItem = nil
      self.hasFailedToCreateStatusItem = true
    }
  }

  // MARK: - 私有：标题更新（去重兜底，R3.3）

  private func setText(_ text: String) {
    DispatchQueue.main.async {
      // 状态栏文字
      if let btn = self.statusItem?.button, btn.title != text {
        btn.title = text
      }
      // 菜单第一项（当前歌曲信息）同步刷新；Dart 侧推送的是已经计算好的
      // 当前歌词或 "标题 - 艺术家" 字符串，直接复用作为标题项文案。
      if let item = self.menuTitleItem, item.title != text {
        item.title = text
      }
    }
  }

  // MARK: - 私有：显示主窗口

  fileprivate func showMainWindow() {
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      // 选第一个非 statusItem 的窗口
      let target = NSApp.windows.first(where: { $0.contentViewController is FlutterViewController })
        ?? NSApp.windows.first
      target?.makeKeyAndOrderFront(nil)
    }
  }

  // MARK: - 菜单构建（Task 8）

  /// 构建状态栏弹出菜单，按需求 R4.2 严格 9 项：
  ///   1. 当前歌曲信息（不可点击的标题项；初始 "未在播放"，由 setText 刷新）
  ///   2. 分隔符
  ///   3. 播放 / 暂停
  ///   4. 上一首
  ///   5. 下一首
  ///   6. 分隔符
  ///   7. 显示主窗口
  ///   8. 分隔符
  ///   9. 关闭状态栏歌词
  ///
  /// 每个动作菜单项 `target = self` 并绑定到对应的 `@objc` selector；
  /// status item 本身不设置 `button.action / target`，依赖 NSStatusItem
  /// 默认菜单展开行为（用户需求确认）。
  fileprivate func buildMenu() -> NSMenu {
    let m = NSMenu()
    m.autoenablesItems = false  // 我们自己控制 isEnabled

    // 1) 当前歌曲信息（标题项，不可点击）
    let titleItem = NSMenuItem(title: "未在播放", action: nil, keyEquivalent: "")
    titleItem.isEnabled = false
    m.addItem(titleItem)
    self.menuTitleItem = titleItem

    // 2) 分隔符
    m.addItem(NSMenuItem.separator())

    // 3) 播放 / 暂停
    let togglePlayItem = NSMenuItem(
      title: "播放 / 暂停",
      action: #selector(onTogglePlayPause),
      keyEquivalent: ""
    )
    togglePlayItem.target = self
    m.addItem(togglePlayItem)

    // 4) 上一首
    let prevItem = NSMenuItem(
      title: "上一首",
      action: #selector(onPrevious),
      keyEquivalent: ""
    )
    prevItem.target = self
    m.addItem(prevItem)

    // 5) 下一首
    let nextItem = NSMenuItem(
      title: "下一首",
      action: #selector(onNext),
      keyEquivalent: ""
    )
    nextItem.target = self
    m.addItem(nextItem)

    // 6) 分隔符
    m.addItem(NSMenuItem.separator())

    // 7) 显示主窗口
    let showWindowItem = NSMenuItem(
      title: "显示主窗口",
      action: #selector(onShowMainWindow),
      keyEquivalent: ""
    )
    showWindowItem.target = self
    m.addItem(showWindowItem)

    // 8) 分隔符
    m.addItem(NSMenuItem.separator())

    // 9) 关闭状态栏歌词
    let closeItem = NSMenuItem(
      title: "关闭状态栏歌词",
      action: #selector(onCloseStatusBar),
      keyEquivalent: ""
    )
    closeItem.target = self
    m.addItem(closeItem)

    self.menu = m
    return m
  }

  // MARK: - 菜单回调（@objc）

  @objc private func onTogglePlayPause() {
    invoke("togglePlayPause")
  }

  @objc private func onPrevious() {
    invoke("previous")
  }

  @objc private func onNext() {
    invoke("next")
  }

  /// 显示主窗口：直接由原生层处理，不经过 Dart 往返（更顺滑）。
  @objc private func onShowMainWindow() {
    showMainWindow()
  }

  /// 关闭状态栏歌词：先通知 Dart 持久化偏好为 false，再立即从原生层 tearDown，
  /// 让用户体感到的 UI 立即消失（无须等 Dart 往返完成）。
  @objc private func onCloseStatusBar() {
    invoke("closeStatusBar")
    tearDown()
  }

  // MARK: - 内部工具：通过 channel 通知 Dart

  fileprivate func invoke(_ action: String) {
    DispatchQueue.main.async {
      self.channel.invokeMethod("onMenuAction", arguments: action)
    }
  }
}
