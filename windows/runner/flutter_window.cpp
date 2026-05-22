#include "flutter_window.h"

#include <optional>
#include <shellapi.h>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // 注册并初始化用于与 Dart 通信的 MethodChannel
  method_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.jmusic.app/tray",
      &flutter::StandardMethodCodec::GetInstance());

  // 创建悬浮歌词窗口实例
  lyrics_overlay_ = std::make_unique<LyricsOverlay>();
  lyrics_overlay_->Create();

  method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name().compare("updateTitle") == 0) {
          const auto* arguments = std::get_if<std::string>(call.arguments());
          if (arguments) {
            std::string title = *arguments;
            // 将 UTF-8 std::string 转换为 std::wstring 供 Windows API 使用
            int len = MultiByteToWideChar(CP_UTF8, 0, title.c_str(), -1, nullptr, 0);
            if (len > 0) {
              std::wstring wtitle(len, 0);
              MultiByteToWideChar(CP_UTF8, 0, title.c_str(), -1, &wtitle[0], len);
              if (!wtitle.empty() && wtitle.back() == 0) {
                wtitle.pop_back();
              }

              HWND hwnd = GetHandle();
              if (hwnd) {
                // 1. 修改窗口标题（用于任务栏最小化时的显示）
                SetWindowTextW(hwnd, wtitle.c_str());

                // 2. 修改系统托盘的鼠标悬停浮动提示（Title）
                NOTIFYICONDATAW nid = {};
                nid.cbSize = sizeof(NOTIFYICONDATAW);
                nid.hWnd = hwnd;
                nid.uID = 1;
                nid.uFlags = NIF_TIP;
                wcsncpy_s(nid.szTip, wtitle.c_str(), _countof(nid.szTip));
                Shell_NotifyIconW(NIM_MODIFY, &nid);
              }
            }
            result->Success();
          } else {
            result->Error("BAD_ARGS", "Expected string argument");
          }
        } else if (call.method_name().compare("showLyricsOverlay") == 0) {
          // 显示悬浮歌词
          if (lyrics_overlay_) {
            lyrics_overlay_->Show(true);
          }
          result->Success();
        } else if (call.method_name().compare("hideLyricsOverlay") == 0) {
          // 隐藏悬浮歌词
          if (lyrics_overlay_) {
            lyrics_overlay_->Show(false);
          }
          result->Success();
        } else if (call.method_name().compare("updateLyrics") == 0) {
          // 更新歌词文本：参数为 Map {"current": "...", "next": "..."}
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
            std::wstring current_line, next_line;

            auto it_current = args->find(flutter::EncodableValue("current"));
            if (it_current != args->end()) {
              const auto* s = std::get_if<std::string>(&it_current->second);
              if (s) {
                int len = MultiByteToWideChar(CP_UTF8, 0, s->c_str(), -1, nullptr, 0);
                if (len > 0) {
                  current_line.resize(len - 1);
                  MultiByteToWideChar(CP_UTF8, 0, s->c_str(), -1, &current_line[0], len);
                }
              }
            }

            auto it_next = args->find(flutter::EncodableValue("next"));
            if (it_next != args->end()) {
              const auto* s = std::get_if<std::string>(&it_next->second);
              if (s) {
                int len = MultiByteToWideChar(CP_UTF8, 0, s->c_str(), -1, nullptr, 0);
                if (len > 0) {
                  next_line.resize(len - 1);
                  MultiByteToWideChar(CP_UTF8, 0, s->c_str(), -1, &next_line[0], len);
                }
              }
            }

            if (lyrics_overlay_) {
              lyrics_overlay_->UpdateLyrics(current_line, next_line);
            }
            result->Success();
          } else {
            result->Error("BAD_ARGS", "Expected map argument with 'current' and 'next' keys");
          }
        } else if (call.method_name().compare("isLyricsOverlayVisible") == 0) {
          // 查询悬浮歌词是否可见
          bool visible = lyrics_overlay_ && lyrics_overlay_->IsVisible();
          result->Success(flutter::EncodableValue(visible));
        } else if (call.method_name().compare("getHwnd") == 0) {
          // 返回窗口句柄（HWND）给 Dart 端，用于初始化系统媒体控制
          HWND hwnd = GetHandle();
          int64_t hwnd_value = reinterpret_cast<int64_t>(hwnd);
          result->Success(flutter::EncodableValue(hwnd_value));
        } else if (call.method_name().compare("updatePlayMode") == 0) {
          // 更新当前播放模式文本（用于托盘菜单显示）
          const auto* arguments = std::get_if<std::string>(call.arguments());
          if (arguments) {
            int len = MultiByteToWideChar(CP_UTF8, 0, arguments->c_str(), -1, nullptr, 0);
            if (len > 0) {
              current_play_mode_label_.resize(len - 1);
              MultiByteToWideChar(CP_UTF8, 0, arguments->c_str(), -1, &current_play_mode_label_[0], len);
            }
            result->Success();
          } else {
            result->Error("BAD_ARGS", "Expected string argument");
          }
        } else {
          result->NotImplemented();
        }
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  // 初始化并添加系统托盘图标
  AddTrayIcon(GetHandle());

  return true;
}

void FlutterWindow::OnDestroy() {
  // 移除系统托盘图标
  RemoveTrayIcon(GetHandle());

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  switch (message) {
    case WM_CLOSE:
      if (!is_exiting_) {
        // 关闭主窗口时隐藏它，实现“最小化到托盘”的效果
        ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;

    case WM_TRAY_ICON:
      if (lparam == WM_LBUTTONUP) {
        // 左键点击托盘：显示并恢复主窗口
        ShowWindow(hwnd, SW_SHOW);
        ShowWindow(hwnd, SW_RESTORE);
        SetForegroundWindow(hwnd);
      } else if (lparam == WM_RBUTTONUP) {
        // 右键点击托盘：弹出上下文菜单
        ShowTrayPopupMenu(hwnd);
      }
      return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

// 添加系统托盘图标的实现
void FlutterWindow::AddTrayIcon(HWND hwnd) {
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(NOTIFYICONDATAW);
  nid.hWnd = hwnd;
  nid.uID = 1; // 托盘图标的唯一 ID
  nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid.uCallbackMessage = WM_TRAY_ICON;
  nid.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcsncpy_s(nid.szTip, L"JMusic", _countof(nid.szTip));

  Shell_NotifyIconW(NIM_ADD, &nid);
}

// 移除系统托盘图标的实现
void FlutterWindow::RemoveTrayIcon(HWND hwnd) {
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(NOTIFYICONDATAW);
  nid.hWnd = hwnd;
  nid.uID = 1;

  Shell_NotifyIconW(NIM_DELETE, &nid);
}

// 弹出系统托盘右键菜单的实现
void FlutterWindow::ShowTrayPopupMenu(HWND hwnd) {
  HMENU hMenu = CreatePopupMenu();
  if (hMenu) {
    // 菜单项：显示主窗口
    AppendMenuW(hMenu, MF_STRING, 1001, L"显示主窗口");
    AppendMenuW(hMenu, MF_SEPARATOR, 0, nullptr);

    // 播放控制
    AppendMenuW(hMenu, MF_STRING, 1005, L"上一曲");
    AppendMenuW(hMenu, MF_STRING, 1006, L"暂停/播放");
    AppendMenuW(hMenu, MF_STRING, 1007, L"下一曲");
    AppendMenuW(hMenu, MF_STRING, 1008, current_play_mode_label_.c_str());
    AppendMenuW(hMenu, MF_SEPARATOR, 0, nullptr);

    // 桌面歌词开关（根据当前状态显示勾选）
    bool lyrics_visible = lyrics_overlay_ && lyrics_overlay_->IsVisible();
    AppendMenuW(hMenu, MF_STRING | (lyrics_visible ? MF_CHECKED : MF_UNCHECKED),
                1003, L"桌面歌词");

    // 解锁歌词位置（仅在歌词可见时有效）
    if (lyrics_visible) {
      bool lyrics_locked = lyrics_overlay_ && lyrics_overlay_->IsLocked();
      AppendMenuW(hMenu, MF_STRING | (lyrics_locked ? MF_UNCHECKED : MF_CHECKED),
                  1004, L"解锁歌词位置");
    }

    AppendMenuW(hMenu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(hMenu, MF_STRING, 1002, L"退出");

    POINT pt;
    GetCursorPos(&pt);

    // 必须在显示菜单前设置窗口为前台窗口，否则在别处点击时菜单不会自动消失
    SetForegroundWindow(hwnd);

    int tracking_flags = TPM_LEFTALIGN | TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY;
    UINT cmd = TrackPopupMenu(hMenu, tracking_flags, pt.x, pt.y, 0, hwnd, nullptr);
    DestroyMenu(hMenu);

    if (cmd == 1001) {
      // 显示并恢复窗口
      ShowWindow(hwnd, SW_SHOW);
      ShowWindow(hwnd, SW_RESTORE);
      SetForegroundWindow(hwnd);
    } else if (cmd == 1002) {
      // 标记正在退出程序，并销毁窗口
      is_exiting_ = true;
      DestroyWindow(hwnd);
    } else if (cmd == 1003) {
      // 切换桌面歌词显示
      if (lyrics_overlay_) {
        lyrics_overlay_->Show(!lyrics_visible);
      }
    } else if (cmd == 1004) {
      // 切换歌词锁定状态
      if (lyrics_overlay_) {
        lyrics_overlay_->SetLocked(!lyrics_overlay_->IsLocked());
      }
    } else if (cmd == 1005) {
      // 上一曲：通过 MethodChannel 通知 Dart
      if (method_channel_) {
        method_channel_->InvokeMethod("onTrayAction", std::make_unique<flutter::EncodableValue>("previous"));
      }
    } else if (cmd == 1006) {
      // 暂停/播放
      if (method_channel_) {
        method_channel_->InvokeMethod("onTrayAction", std::make_unique<flutter::EncodableValue>("togglePlayPause"));
      }
    } else if (cmd == 1007) {
      // 下一曲
      if (method_channel_) {
        method_channel_->InvokeMethod("onTrayAction", std::make_unique<flutter::EncodableValue>("next"));
      }
    } else if (cmd == 1008) {
      // 切换播放模式：顺序 -> 随机 -> 单曲循环
      if (method_channel_) {
        method_channel_->InvokeMethod("onTrayAction", std::make_unique<flutter::EncodableValue>("togglePlayMode"));
      }
    }
  }
}
