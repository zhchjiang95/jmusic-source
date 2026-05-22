#ifndef RUNNER_LYRICS_OVERLAY_H_
#define RUNNER_LYRICS_OVERLAY_H_

#include <windows.h>
#include <gdiplus.h>
#include <string>

#pragma comment(lib, "gdiplus.lib")

/// 桌面悬浮歌词窗口
/// 使用 Win32 Layered Window + GDI+ 实现透明背景、描边文字渲染
class LyricsOverlay {
 public:
  LyricsOverlay();
  ~LyricsOverlay();

  /// 创建并显示悬浮歌词窗口
  bool Create();

  /// 销毁窗口
  void Destroy();

  /// 显示/隐藏窗口
  void Show(bool visible);

  /// 更新歌词文本（当前行 + 下一行）
  void UpdateLyrics(const std::wstring& current_line, const std::wstring& next_line);

  /// 设置字体大小
  void SetFontSize(int size);

  /// 获取当前字体大小
  int GetFontSize() const { return font_size_; }

  /// 设置锁定状态（锁定时鼠标穿透）
  void SetLocked(bool locked);

  /// 获取锁定状态
  bool IsLocked() const { return is_locked_; }

  /// 窗口是否可见
  bool IsVisible() const { return is_visible_; }

  /// 获取窗口句柄
  HWND GetHandle() const { return hwnd_; }

 private:
  /// 重绘歌词内容（使用 UpdateLayeredWindow）
  void Repaint();

  /// 计算窗口尺寸并居中到屏幕底部
  void RepositionWindow();

  /// 保存窗口位置到注册表
  void SavePosition();

  /// 从注册表加载窗口位置
  bool LoadPosition(int& x, int& y);

  /// 显示/隐藏控制条
  void ShowControlBar(bool show);

  /// 窗口过程
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);

  /// 处理鼠标消息（控制条按钮点击检测）
  void OnMouseMove(int x, int y);
  void OnLButtonDown(int x, int y);
  void OnLButtonUp(int x, int y);

  HWND hwnd_ = nullptr;
  bool is_visible_ = false;
  bool is_locked_ = false;
  bool is_dragging_ = false;
  bool show_controls_ = false;
  POINT drag_start_ = {0, 0};
  POINT window_start_ = {0, 0};

  std::wstring current_line_;
  std::wstring next_line_;
  int font_size_ = 24;

  // GDI+ 相关
  ULONG_PTR gdiplus_token_ = 0;

  // 控制条按钮区域（相对于窗口客户区）
  RECT btn_close_ = {0};
  RECT btn_lock_ = {0};
  RECT btn_font_up_ = {0};
  RECT btn_font_down_ = {0};

  // 窗口尺寸
  int window_width_ = 800;
  int window_height_ = 100;

  // 是否使用自定义位置（用户拖拽过）
  bool has_custom_position_ = false;
};

#endif  // RUNNER_LYRICS_OVERLAY_H_
