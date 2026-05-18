#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// 自定义系统托盘消息 ID
#define WM_TRAY_ICON (WM_USER + 100)

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // 添加系统托盘图标
  void AddTrayIcon(HWND hwnd);

  // 移除系统托盘图标
  void RemoveTrayIcon(HWND hwnd);

  // 弹出系统托盘右键菜单
  void ShowTrayPopupMenu(HWND hwnd);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // 是否正在退出程序（点击托盘“退出”菜单时为 true，以允许真正的关闭）
  bool is_exiting_ = false;

  // 用于接收 Dart 传递信息的 MethodChannel
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
