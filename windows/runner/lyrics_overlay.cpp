#include "lyrics_overlay.h"

#include <algorithm>
#include <cmath>

namespace {

constexpr const wchar_t kOverlayClassName[] = L"JMUSIC_LYRICS_OVERLAY";
constexpr const wchar_t kRegKeyPath[] = L"Software\\JMusic\\LyricsOverlay";
constexpr int kControlBarHeight = 32;
constexpr int kBtnSize = 28;
constexpr int kBtnMargin = 6;
constexpr int kBottomMargin = 80;  // 距离屏幕底部的距离

static bool g_class_registered = false;

}  // namespace

LyricsOverlay::LyricsOverlay() {}

LyricsOverlay::~LyricsOverlay() {
  Destroy();
}

bool LyricsOverlay::Create() {
  // 初始化 GDI+
  Gdiplus::GdiplusStartupInput gdiplusStartupInput;
  Gdiplus::GdiplusStartup(&gdiplus_token_, &gdiplusStartupInput, nullptr);

  // 注册窗口类
  if (!g_class_registered) {
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(WNDCLASSEXW);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = LyricsOverlay::WndProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = nullptr;
    wc.lpszClassName = kOverlayClassName;
    RegisterClassExW(&wc);
    g_class_registered = true;
  }

  // 计算初始窗口大小
  window_width_ = 800;
  window_height_ = font_size_ * 2 + 30 + kControlBarHeight;

  // 获取屏幕尺寸，默认底部居中
  int screen_w = GetSystemMetrics(SM_CXSCREEN);
  int screen_h = GetSystemMetrics(SM_CYSCREEN);
  int x = (screen_w - window_width_) / 2;
  int y = screen_h - window_height_ - kBottomMargin;

  // 尝试加载保存的位置
  int saved_x, saved_y;
  if (LoadPosition(saved_x, saved_y)) {
    x = saved_x;
    y = saved_y;
    has_custom_position_ = true;
  }

  // 创建分层窗口（WS_EX_LAYERED 支持透明，WS_EX_TOPMOST 置顶，WS_EX_TOOLWINDOW 不在任务栏显示）
  hwnd_ = CreateWindowExW(
      WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
      kOverlayClassName,
      L"JMusic Lyrics",
      WS_POPUP,
      x, y, window_width_, window_height_,
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!hwnd_) {
    return false;
  }

  // 初始状态为锁定（鼠标穿透），默认显示
  SetLocked(true);
  Show(true);

  return true;
}

void LyricsOverlay::Destroy() {
  if (hwnd_) {
    SavePosition();
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  if (gdiplus_token_) {
    Gdiplus::GdiplusShutdown(gdiplus_token_);
    gdiplus_token_ = 0;
  }
}

void LyricsOverlay::Show(bool visible) {
  if (!hwnd_) return;
  is_visible_ = visible;
  ShowWindow(hwnd_, visible ? SW_SHOWNOACTIVATE : SW_HIDE);
  if (visible) {
    Repaint();
  }
}

void LyricsOverlay::UpdateLyrics(const std::wstring& current_line, const std::wstring& next_line) {
  if (current_line_ == current_line && next_line_ == next_line) return;
  current_line_ = current_line;
  next_line_ = next_line;
  if (is_visible_) {
    Repaint();
  }
}

void LyricsOverlay::SetFontSize(int size) {
  size = std::clamp(size, 16, 48);
  if (font_size_ == size) return;
  font_size_ = size;
  RepositionWindow();
  if (is_visible_) {
    Repaint();
  }
}

void LyricsOverlay::SetLocked(bool locked) {
  if (!hwnd_) return;
  is_locked_ = locked;

  LONG ex_style = GetWindowLong(hwnd_, GWL_EXSTYLE);
  if (locked) {
    // 锁定：添加鼠标穿透
    ex_style |= WS_EX_TRANSPARENT;
    show_controls_ = false;
  } else {
    // 解锁：移除鼠标穿透
    ex_style &= ~WS_EX_TRANSPARENT;
  }
  SetWindowLong(hwnd_, GWL_EXSTYLE, ex_style);

  if (is_visible_) {
    Repaint();
  }
}

void LyricsOverlay::Repaint() {
  if (!hwnd_ || !gdiplus_token_) return;

  // 重新计算窗口高度
  int lyrics_height = font_size_ * 2 + 20;
  int total_height = lyrics_height + (show_controls_ ? kControlBarHeight : 0);
  window_height_ = total_height;

  // 创建兼容 DC 和位图
  HDC screen_dc = GetDC(nullptr);
  HDC mem_dc = CreateCompatibleDC(screen_dc);

  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = window_width_;
  bmi.bmiHeader.biHeight = -window_height_;  // 自顶向下
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  HBITMAP hbmp = CreateDIBSection(mem_dc, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
  HBITMAP old_bmp = (HBITMAP)SelectObject(mem_dc, hbmp);

  // 清空为全透明
  memset(bits, 0, window_width_ * window_height_ * 4);

  // 使用 GDI+ 绘制
  {
    Gdiplus::Graphics graphics(mem_dc);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeHighQuality);
    graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAlias);

    // 绘制控制条（如果显示）
    if (show_controls_) {
      // 半透明黑色背景条
      Gdiplus::SolidBrush bar_brush(Gdiplus::Color(180, 30, 30, 30));
      Gdiplus::Rect bar_rect(0, 0, window_width_, kControlBarHeight);
      graphics.FillRectangle(&bar_brush, bar_rect);

      // 绘制按钮
      Gdiplus::Font btn_font(L"Segoe UI Symbol", 14, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
      Gdiplus::SolidBrush btn_text_brush(Gdiplus::Color(255, 255, 255, 255));
      Gdiplus::StringFormat btn_format;
      btn_format.SetAlignment(Gdiplus::StringAlignmentCenter);
      btn_format.SetLineAlignment(Gdiplus::StringAlignmentCenter);

      // 按钮布局：居中排列
      int total_btns_width = kBtnSize * 4 + kBtnMargin * 3;
      int btn_start_x = (window_width_ - total_btns_width) / 2;
      int btn_y = (kControlBarHeight - kBtnSize) / 2;

      // 字号减小按钮 A-
      btn_font_down_ = {btn_start_x, btn_y, btn_start_x + kBtnSize, btn_y + kBtnSize};
      Gdiplus::RectF rf_down((float)btn_font_down_.left, (float)btn_font_down_.top, (float)kBtnSize, (float)kBtnSize);
      Gdiplus::SolidBrush btn_bg(Gdiplus::Color(100, 80, 80, 80));
      graphics.FillRectangle(&btn_bg, rf_down);
      graphics.DrawString(L"A-", -1, &btn_font, rf_down, &btn_format, &btn_text_brush);

      // 字号增大按钮 A+
      btn_font_up_ = {btn_start_x + kBtnSize + kBtnMargin, btn_y,
                      btn_start_x + kBtnSize * 2 + kBtnMargin, btn_y + kBtnSize};
      Gdiplus::RectF rf_up((float)btn_font_up_.left, (float)btn_font_up_.top, (float)kBtnSize, (float)kBtnSize);
      graphics.FillRectangle(&btn_bg, rf_up);
      graphics.DrawString(L"A+", -1, &btn_font, rf_up, &btn_format, &btn_text_brush);

      // 锁定/解锁按钮
      btn_lock_ = {btn_start_x + (kBtnSize + kBtnMargin) * 2, btn_y,
                   btn_start_x + kBtnSize * 3 + kBtnMargin * 2, btn_y + kBtnSize};
      Gdiplus::RectF rf_lock((float)btn_lock_.left, (float)btn_lock_.top, (float)kBtnSize, (float)kBtnSize);
      graphics.FillRectangle(&btn_bg, rf_lock);
      graphics.DrawString(is_locked_ ? L"\x25C9" : L"\x25CE", -1, &btn_font, rf_lock, &btn_format, &btn_text_brush);

      // 关闭按钮
      btn_close_ = {btn_start_x + (kBtnSize + kBtnMargin) * 3, btn_y,
                    btn_start_x + kBtnSize * 4 + kBtnMargin * 3, btn_y + kBtnSize};
      Gdiplus::RectF rf_close((float)btn_close_.left, (float)btn_close_.top, (float)kBtnSize, (float)kBtnSize);
      Gdiplus::SolidBrush close_bg(Gdiplus::Color(100, 180, 50, 50));
      graphics.FillRectangle(&close_bg, rf_close);
      graphics.DrawString(L"\x2715", -1, &btn_font, rf_close, &btn_format, &btn_text_brush);
    }

    // 绘制歌词文字（带阴影效果）
    int lyrics_y_offset = show_controls_ ? kControlBarHeight : 0;

    Gdiplus::FontFamily fontFamily(L"Microsoft YaHei");
    if (!fontFamily.IsAvailable()) {
      // 回退字体
      Gdiplus::FontFamily fallback(L"SimHei");
    }

    // 当前行（白色 + 淡黑色阴影）
    {
      Gdiplus::StringFormat format;
      format.SetAlignment(Gdiplus::StringAlignmentCenter);
      format.SetLineAlignment(Gdiplus::StringAlignmentNear);

      const wchar_t* text = current_line_.empty() ? L" " : current_line_.c_str();
      Gdiplus::RectF layout(0, (float)lyrics_y_offset + 5, (float)window_width_, (float)font_size_ + 10);

      // 阴影（偏移 2px，淡黑色半透明）
      {
        Gdiplus::GraphicsPath shadow_path;
        shadow_path.AddString(text, -1, &fontFamily, Gdiplus::FontStyleBold, (float)font_size_,
            Gdiplus::RectF(layout.X + 1.5f, layout.Y + 1.5f, layout.Width, layout.Height), &format);
        Gdiplus::SolidBrush shadow_brush(Gdiplus::Color(120, 0, 0, 0));
        graphics.FillPath(&shadow_brush, &shadow_path);
      }

      // 正文（白色）
      {
        Gdiplus::GraphicsPath path;
        path.AddString(text, -1, &fontFamily, Gdiplus::FontStyleBold, (float)font_size_, layout, &format);
        Gdiplus::SolidBrush fill_brush(Gdiplus::Color(255, 255, 255, 255));
        graphics.FillPath(&fill_brush, &path);
      }
    }

    // 下一行（稍透明白色 + 淡黑色阴影）
    {
      Gdiplus::StringFormat format;
      format.SetAlignment(Gdiplus::StringAlignmentCenter);
      format.SetLineAlignment(Gdiplus::StringAlignmentNear);

      const wchar_t* text = next_line_.empty() ? L" " : next_line_.c_str();
      Gdiplus::RectF layout(0, (float)(lyrics_y_offset + font_size_ + 15), (float)window_width_, (float)font_size_ + 10);

      // 阴影
      {
        Gdiplus::GraphicsPath shadow_path;
        shadow_path.AddString(text, -1, &fontFamily, Gdiplus::FontStyleRegular, (float)(font_size_ - 4),
            Gdiplus::RectF(layout.X + 1.5f, layout.Y + 1.5f, layout.Width, layout.Height), &format);
        Gdiplus::SolidBrush shadow_brush(Gdiplus::Color(100, 0, 0, 0));
        graphics.FillPath(&shadow_brush, &shadow_path);
      }

      // 正文
      {
        Gdiplus::GraphicsPath path;
        path.AddString(text, -1, &fontFamily, Gdiplus::FontStyleRegular, (float)(font_size_ - 4), layout, &format);
        Gdiplus::SolidBrush fill_brush(Gdiplus::Color(200, 255, 255, 255));
        graphics.FillPath(&fill_brush, &path);
      }
    }
  }

  // 使用 UpdateLayeredWindow 实现逐像素透明
  POINT pt_src = {0, 0};
  SIZE sz = {window_width_, window_height_};
  BLENDFUNCTION blend = {};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha = 255;
  blend.AlphaFormat = AC_SRC_ALPHA;

  POINT pt_dst;
  RECT wnd_rect;
  GetWindowRect(hwnd_, &wnd_rect);
  pt_dst.x = wnd_rect.left;
  pt_dst.y = wnd_rect.top;

  UpdateLayeredWindow(hwnd_, screen_dc, &pt_dst, &sz, mem_dc, &pt_src, 0, &blend, ULW_ALPHA);

  // 清理
  SelectObject(mem_dc, old_bmp);
  DeleteObject(hbmp);
  DeleteDC(mem_dc);
  ReleaseDC(nullptr, screen_dc);
}

void LyricsOverlay::RepositionWindow() {
  if (!hwnd_) return;

  int new_height = font_size_ * 2 + 20 + (show_controls_ ? kControlBarHeight : 0);
  window_height_ = new_height;

  if (!has_custom_position_) {
    // 重新居中到屏幕底部
    int screen_w = GetSystemMetrics(SM_CXSCREEN);
    int screen_h = GetSystemMetrics(SM_CYSCREEN);
    int x = (screen_w - window_width_) / 2;
    int y = screen_h - window_height_ - kBottomMargin;
    SetWindowPos(hwnd_, HWND_TOPMOST, x, y, window_width_, window_height_,
                 SWP_NOACTIVATE);
  } else {
    RECT rc;
    GetWindowRect(hwnd_, &rc);
    SetWindowPos(hwnd_, HWND_TOPMOST, rc.left, rc.top, window_width_, window_height_,
                 SWP_NOACTIVATE);
  }
}

void LyricsOverlay::SavePosition() {
  if (!hwnd_) return;

  RECT rc;
  GetWindowRect(hwnd_, &rc);

  HKEY hKey;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kRegKeyPath, 0, nullptr,
                      REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hKey, nullptr) == ERROR_SUCCESS) {
    DWORD x = (DWORD)rc.left;
    DWORD y = (DWORD)rc.top;
    DWORD fs = (DWORD)font_size_;
    RegSetValueExW(hKey, L"X", 0, REG_DWORD, (BYTE*)&x, sizeof(DWORD));
    RegSetValueExW(hKey, L"Y", 0, REG_DWORD, (BYTE*)&y, sizeof(DWORD));
    RegSetValueExW(hKey, L"FontSize", 0, REG_DWORD, (BYTE*)&fs, sizeof(DWORD));
    RegCloseKey(hKey);
  }
}

bool LyricsOverlay::LoadPosition(int& x, int& y) {
  HKEY hKey;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRegKeyPath, 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
    DWORD val_x, val_y, val_fs;
    DWORD size = sizeof(DWORD);
    bool has_pos = false;

    if (RegQueryValueExW(hKey, L"X", nullptr, nullptr, (BYTE*)&val_x, &size) == ERROR_SUCCESS &&
        RegQueryValueExW(hKey, L"Y", nullptr, nullptr, (BYTE*)&val_y, &size) == ERROR_SUCCESS) {
      x = (int)val_x;
      y = (int)val_y;
      has_pos = true;
    }

    size = sizeof(DWORD);
    if (RegQueryValueExW(hKey, L"FontSize", nullptr, nullptr, (BYTE*)&val_fs, &size) == ERROR_SUCCESS) {
      font_size_ = std::clamp((int)val_fs, 16, 48);
    }

    RegCloseKey(hKey);
    return has_pos;
  }
  return false;
}

void LyricsOverlay::ShowControlBar(bool show) {
  if (show_controls_ == show) return;
  show_controls_ = show;
  RepositionWindow();
  Repaint();
}

void LyricsOverlay::OnMouseMove(int x, int y) {
  // 鼠标在窗口内时显示控制条
  if (!show_controls_) {
    ShowControlBar(true);
  }

  // 拖拽处理
  if (is_dragging_) {
    POINT cursor;
    GetCursorPos(&cursor);
    int new_x = window_start_.x + (cursor.x - drag_start_.x);
    int new_y = window_start_.y + (cursor.y - drag_start_.y);
    SetWindowPos(hwnd_, HWND_TOPMOST, new_x, new_y, 0, 0,
                 SWP_NOSIZE | SWP_NOACTIVATE);
    has_custom_position_ = true;
  }
}

void LyricsOverlay::OnLButtonDown(int x, int y) {
  // 检查是否点击了按钮
  POINT pt = {x, y};

  if (PtInRect(&btn_close_, pt)) {
    // 关闭（隐藏）
    Show(false);
    return;
  }

  if (PtInRect(&btn_lock_, pt)) {
    // 锁定
    SetLocked(true);
    return;
  }

  if (PtInRect(&btn_font_up_, pt)) {
    SetFontSize(font_size_ + 2);
    return;
  }

  if (PtInRect(&btn_font_down_, pt)) {
    SetFontSize(font_size_ - 2);
    return;
  }

  // 否则开始拖拽
  is_dragging_ = true;
  SetCapture(hwnd_);
  GetCursorPos(&drag_start_);
  RECT rc;
  GetWindowRect(hwnd_, &rc);
  window_start_ = {rc.left, rc.top};
}

void LyricsOverlay::OnLButtonUp(int x, int y) {
  if (is_dragging_) {
    is_dragging_ = false;
    ReleaseCapture();
    SavePosition();
  }
}

LRESULT CALLBACK LyricsOverlay::WndProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  LyricsOverlay* self = nullptr;

  if (msg == WM_NCCREATE) {
    auto cs = reinterpret_cast<CREATESTRUCT*>(lparam);
    self = static_cast<LyricsOverlay*>(cs->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  } else {
    self = reinterpret_cast<LyricsOverlay*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  }

  if (!self) {
    return DefWindowProc(hwnd, msg, wparam, lparam);
  }

  switch (msg) {
    case WM_MOUSEMOVE:
      self->OnMouseMove(LOWORD(lparam), HIWORD(lparam));
      // 设置鼠标追踪以接收 WM_MOUSELEAVE
      {
        TRACKMOUSEEVENT tme = {};
        tme.cbSize = sizeof(tme);
        tme.dwFlags = TME_LEAVE;
        tme.hwndTrack = hwnd;
        TrackMouseEvent(&tme);
      }
      return 0;

    case WM_MOUSELEAVE:
      // 鼠标离开时隐藏控制条
      if (!self->is_dragging_) {
        self->ShowControlBar(false);
      }
      return 0;

    case WM_LBUTTONDOWN:
      self->OnLButtonDown(LOWORD(lparam), HIWORD(lparam));
      return 0;

    case WM_LBUTTONUP:
      self->OnLButtonUp(LOWORD(lparam), HIWORD(lparam));
      return 0;

    case WM_DESTROY:
      self->hwnd_ = nullptr;
      return 0;
  }

  return DefWindowProc(hwnd, msg, wparam, lparam);
}
