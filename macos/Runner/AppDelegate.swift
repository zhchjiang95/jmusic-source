import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {

  // MARK: - 状态栏歌词与窗口委托

  private var statusBar: StatusBarLyricsController?
  private let mainWindowDelegate = MainWindowDelegate()

  /// 由 MainFlutterWindow.awakeFromNib 在 FlutterViewController 创建完毕后调用。
  /// 此时 binaryMessenger 已经可用，时序比 applicationDidFinishLaunching 更确定。
  func attachStatusBarLyrics(messenger: FlutterBinaryMessenger, window: NSWindow) {
    // 拦截关闭按钮：用户体验决策——关闭按钮 = 隐藏窗口，不退出
    window.delegate = mainWindowDelegate

    // 注册菜单栏歌词 channel handler
    statusBar = StatusBarLyricsController(messenger: messenger)
  }

  // MARK: - 关闭按钮 / 退出策略

  /// 配合 MainWindowDelegate.windowShouldClose：所有窗口隐藏时也不退出，
  /// 应用继续在后台运行；用户通过状态栏菜单的「显示主窗口」、
  /// Dock 点击或 Cmd+Q 控制可见性与退出。
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// 处理 Dock 图标点击：当没有可见窗口时，把主窗口重新带回前台。
  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      let target = NSApp.windows.first(where: { $0.contentViewController is FlutterViewController })
        ?? NSApp.windows.first
      target?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // MARK: - 退出清理

  /// 应用即将退出：主动移除 NSStatusItem，避免菜单栏残留（R6.3）。
  override func applicationWillTerminate(_ notification: Notification) {
    statusBar?.tearDown()
    super.applicationWillTerminate(notification)
  }
}
