import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // 设置默认窗口大小并居中
    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
    let width: CGFloat = 410
    let height: CGFloat = 750
    let x = screenFrame.origin.x + (screenFrame.width - width) / 2
    let y = screenFrame.origin.y + (screenFrame.height - height) / 2
    self.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 把状态栏歌词控制器与窗口委托交给 AppDelegate 持有，避免在
    // applicationDidFinishLaunching 时再去搜索窗口（时序更确定）。
    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.attachStatusBarLyrics(
        messenger: flutterViewController.engine.binaryMessenger,
        window: self
      )
    } else {
      NSLog("[StatusBarLyrics] AppDelegate not found, status bar feature will be unavailable")
    }

    super.awakeFromNib()
  }
}
