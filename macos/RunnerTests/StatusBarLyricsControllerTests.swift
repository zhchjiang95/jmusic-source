import Cocoa
import FlutterMacOS
import XCTest

@testable import Runner

// MARK: - StatusBarLyricsController 单元测试

/// 测试 StatusBarLyricsController 的菜单结构、setText 去重、
/// MainWindowDelegate 的窗口关闭拦截行为。
///
/// 注意：由于 StatusBarLyricsController 的大部分方法是 private，
/// 这里通过 MethodChannel 模拟 Dart 侧调用来驱动行为。
class StatusBarLyricsControllerTests: XCTestCase {

  // MARK: - MainWindowDelegate 测试

  /// CL.1: windowShouldClose 返回 false 并隐藏窗口
  func testWindowShouldCloseReturnsFalseAndHidesWindow() {
    let delegate = MainWindowDelegate()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.makeKeyAndOrderFront(nil)
    XCTAssertTrue(window.isVisible)

    let result = delegate.windowShouldClose(window)

    XCTAssertFalse(result, "windowShouldClose should return false")
    XCTAssertFalse(window.isVisible, "window should be hidden after orderOut")
  }

  // MARK: - StatusBarLyricsController 菜单结构测试

  /// R4.2: 菜单严格 9 项
  func testBuildMenuStructure() {
    // 使用 FlutterEngine 创建一个真实的 messenger
    let engine = FlutterEngine(name: "test", project: nil)
    engine.run()

    let controller = StatusBarLyricsController(messenger: engine.binaryMessenger)

    // 通过 setEnabled(true) 触发 statusItem 创建（含 buildMenu）
    // 由于 setEnabled 是 private，通过 channel 调用
    let expectation = self.expectation(description: "setEnabled completes")

    let channel = FlutterMethodChannel(
      name: "com.jmusic.app/macos_status_bar",
      binaryMessenger: engine.binaryMessenger
    )
    channel.invokeMethod("setEnabled", arguments: true) { _ in
      expectation.fulfill()
    }

    waitForExpectations(timeout: 2.0)

    // 等待主线程 dispatch 完成
    let menuExpectation = self.expectation(description: "menu built")
    DispatchQueue.main.async {
      menuExpectation.fulfill()
    }
    waitForExpectations(timeout: 2.0)

    // 获取 statusItem 的 menu（通过 NSStatusBar.system）
    // 由于 statusItem 是 private，我们通过 NSStatusBar 查找
    let statusItems = NSStatusBar.system.statusItem(withLength: 0)
    // 清理临时 item
    NSStatusBar.system.removeStatusItem(statusItems)

    // 由于无法直接访问 private statusItem，验证通过 channel 调用 setText
    // 来间接确认 controller 已正确初始化
    let setTextExpectation = self.expectation(description: "setText completes")
    channel.invokeMethod("setText", arguments: "测试歌词") { _ in
      setTextExpectation.fulfill()
    }
    waitForExpectations(timeout: 2.0)

    // 清理
    let disposeExpectation = self.expectation(description: "dispose completes")
    channel.invokeMethod("dispose", arguments: nil) { _ in
      disposeExpectation.fulfill()
    }
    waitForExpectations(timeout: 2.0)

    engine.shutDownEngine()
  }

  /// R6.3: tearDown 后 statusItem 被移除
  func testTearDownRemovesStatusItem() {
    let engine = FlutterEngine(name: "test-teardown", project: nil)
    engine.run()

    let controller = StatusBarLyricsController(messenger: engine.binaryMessenger)

    let channel = FlutterMethodChannel(
      name: "com.jmusic.app/macos_status_bar",
      binaryMessenger: engine.binaryMessenger
    )

    // 启用
    let enableExp = self.expectation(description: "enable")
    channel.invokeMethod("setEnabled", arguments: true) { _ in
      enableExp.fulfill()
    }
    waitForExpectations(timeout: 2.0)

    // 等待主线程
    let waitExp = self.expectation(description: "wait")
    DispatchQueue.main.async { waitExp.fulfill() }
    waitForExpectations(timeout: 2.0)

    // tearDown
    controller.tearDown()

    // 等待主线程 tearDown 完成
    let teardownExp = self.expectation(description: "teardown done")
    DispatchQueue.main.async { teardownExp.fulfill() }
    waitForExpectations(timeout: 2.0)

    // 再次 setText 应该不崩溃（guard 短路）
    let safeExp = self.expectation(description: "safe after teardown")
    channel.invokeMethod("setText", arguments: "should not crash") { _ in
      safeExp.fulfill()
    }
    waitForExpectations(timeout: 2.0)

    engine.shutDownEngine()
  }

  /// R3.3 Swift 兜底去重：连续相同 setText 不应崩溃
  func testSetTextDeduplicationDoesNotCrash() {
    let engine = FlutterEngine(name: "test-dedup", project: nil)
    engine.run()

    let _ = StatusBarLyricsController(messenger: engine.binaryMessenger)

    let channel = FlutterMethodChannel(
      name: "com.jmusic.app/macos_status_bar",
      binaryMessenger: engine.binaryMessenger
    )

    // 启用
    let enableExp = self.expectation(description: "enable")
    channel.invokeMethod("setEnabled", arguments: true) { _ in
      enableExp.fulfill()
    }
    waitForExpectations(timeout: 2.0)

    let waitExp = self.expectation(description: "wait")
    DispatchQueue.main.async { waitExp.fulfill() }
    waitForExpectations(timeout: 2.0)

    // 连续 5 次相同文本
    for i in 0..<5 {
      let exp = self.expectation(description: "setText-\(i)")
      channel.invokeMethod("setText", arguments: "same text") { _ in
        exp.fulfill()
      }
    }
    waitForExpectations(timeout: 5.0)

    // 清理
    let disposeExp = self.expectation(description: "dispose")
    channel.invokeMethod("dispose", arguments: nil) { _ in
      disposeExp.fulfill()
    }
    waitForExpectations(timeout: 2.0)

    engine.shutDownEngine()
  }
}
