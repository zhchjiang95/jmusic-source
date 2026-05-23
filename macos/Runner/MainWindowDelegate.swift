import Cocoa

/// 拦截主窗口红色关闭按钮的行为：
///
/// 用户点击关闭按钮时仅隐藏窗口（`orderOut`），不关闭窗口、不触发 NSApp 退出。
/// 应用继续在后台运行，菜单栏歌词保持可见；用户可以通过：
///   - 状态栏菜单的「显示主窗口」
///   - Dock 图标点击（由 AppDelegate.applicationShouldHandleReopen 处理）
///   - 系统菜单 Cmd+Q（正常退出）
/// 重新打开窗口或退出应用。
///
/// 该类故意不持有对 `StatusBarLyricsController` 的引用，保持单一职责。
final class MainWindowDelegate: NSObject, NSWindowDelegate {

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    return false
  }
}
