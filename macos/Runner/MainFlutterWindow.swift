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

    super.awakeFromNib()
  }
}
