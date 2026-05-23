// macOS 菜单栏歌词显示功能
//
// 本文件仅在 macOS 平台真正生效；其他平台调用本文件中的 API 时，
// `MacosStatusBarController` 会通过 `_isMacos()` 守卫直接早返，不会
// 触发任何 MethodChannel 调用，也不会订阅 `playerProvider`。
//
// 当前文件包含的内容（Wave 1：Task 1 + Task 2）：
//   - 常量定义
//   - 纯函数 `truncateByRunes`、`computeStatusBarTitle`
//   - 状态模型 `MacosStatusBarState`
//
// 控制器本身（`MacosStatusBarController`）将在 Wave 2 / Wave 3 任务中加入。

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jmusic/providers/app_providers.dart';

// ---------------------------------------------------------------------------
// 常量
// ---------------------------------------------------------------------------

/// 状态栏未播放或无歌词时的默认标题文案。
/// 对应需求 Glossary 中的 Default_Title 与需求 R3.5 / R3.7 / R2.2。
const String kStatusBarDefaultTitle = 'JMusic';

/// 状态栏标题允许显示的最大 Unicode 码点数。
/// 对应需求 Glossary 中的 Max_Display_Length 与需求 R3.4。
const int kStatusBarMaxDisplayLength = 40;

/// macOS 菜单栏歌词所用的 MethodChannel 名称。
/// 与 Windows tray 的 `com.jmusic.app/tray` 完全隔离（R7.3）。
const String kMacosStatusBarChannel = 'com.jmusic.app/macos_status_bar';

/// SharedPreferences 中持久化「是否启用菜单栏歌词」的键名。
/// 对应需求 Glossary 中的 Status_Bar_Lyrics_Enabled 与需求 R5.4。
const String kStatusBarLyricsEnabledPrefKey = 'status_bar_lyrics_enabled';

// ---------------------------------------------------------------------------
// 纯函数（Task 1）
// ---------------------------------------------------------------------------

/// 按 Unicode 码点截断字符串：
///
/// - 当 `s.runes.length <= maxLen` 时，返回 `s` 本身；
/// - 否则取前 `maxLen` 个码点并在末尾追加省略号 `…`（U+2026）。
///
/// 不会切坏多字节字符（如 emoji、CJK），满足 R3.4。
///
/// `maxLen` 必须 >= 0。当 `maxLen == 0` 且字符串非空时，结果为单独的 `…`。
String truncateByRunes(String s, int maxLen) {
  assert(maxLen >= 0, 'maxLen must be non-negative');
  final runes = s.runes;
  if (runes.length <= maxLen) {
    return s;
  }
  final head = String.fromCharCodes(runes.take(maxLen));
  return '$head\u2026';
}

/// 由 [PlayerState] 计算菜单栏要显示的标题文本。
///
/// 分支顺序（与需求 R2.2 / R3.5 / R3.6 / R3.7 对齐）：
///   1. 当前没有歌曲（`currentSong == null`）→ 返回 [kStatusBarDefaultTitle]
///   2. 没有歌词 / 歌词为空 / 当前播放进度尚未到达第一行歌词
///      → 返回 `truncateByRunes('${title} - ${artist}', maxLen)`
///   3. 否则取最后一个 `timeMs <= position.inMilliseconds` 的行文本
///      → 返回 `truncateByRunes(text, maxLen)`
///
/// 此函数是纯函数：不持有副作用、不依赖 MethodChannel / 偏好存储 / 时间。
/// 可以独立做属性测试（Property 1、Property 2）。
String computeStatusBarTitle(
  PlayerState state, {
  int maxLen = kStatusBarMaxDisplayLength,
}) {
  final song = state.currentSong;
  if (song == null) {
    return kStatusBarDefaultTitle;
  }

  final lyrics = state.lyrics;
  final positionMs = state.position.inMilliseconds;

  // 没有歌词、空歌词、或进度尚未到第一行
  if (lyrics == null || lyrics.lines.isEmpty) {
    return truncateByRunes('${song.title} - ${song.artist}', maxLen);
  }
  final firstTimeMs = lyrics.lines.first.timeMs.toInt();
  if (positionMs < firstTimeMs) {
    return truncateByRunes('${song.title} - ${song.artist}', maxLen);
  }

  // 取最后一个 timeMs <= position 的行
  String currentText = lyrics.lines.first.text;
  for (var i = lyrics.lines.length - 1; i >= 0; i--) {
    final t = lyrics.lines[i].timeMs.toInt();
    if (t <= positionMs) {
      currentText = lyrics.lines[i].text;
      break;
    }
  }
  return truncateByRunes(currentText, maxLen);
}

// ---------------------------------------------------------------------------
// 状态模型（Task 2）
// ---------------------------------------------------------------------------

/// 菜单栏歌词控制器的对外可观察状态。
///
/// - [enabled]：当前是否启用菜单栏歌词。设置页 Switch 直接绑定此字段。
///   默认值为 `true`（R5.4），但在非 macOS 平台 `MacosStatusBarController`
///   会强制使用 `false` 初始化。
/// - [lastPushedTitle]：上一次成功推送给原生层的标题字符串，用于
///   `_pushIfChanged` 的去重（R3.3）。设计上不会被 UI 直接消费。
class MacosStatusBarState {
  final bool enabled;
  final String? lastPushedTitle;

  const MacosStatusBarState({this.enabled = true, this.lastPushedTitle});

  MacosStatusBarState copyWith({
    bool? enabled,
    String? lastPushedTitle,
    bool clearLastPushedTitle = false,
  }) {
    return MacosStatusBarState(
      enabled: enabled ?? this.enabled,
      lastPushedTitle: clearLastPushedTitle
          ? null
          : (lastPushedTitle ?? this.lastPushedTitle),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MacosStatusBarState &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          lastPushedTitle == other.lastPushedTitle;

  @override
  int get hashCode => Object.hash(enabled, lastPushedTitle);

  @override
  String toString() =>
      'MacosStatusBarState(enabled: $enabled, lastPushedTitle: $lastPushedTitle)';
}


// ---------------------------------------------------------------------------
// Controller（Task 3 / 4 / 5 / 6 增量构建）
// ---------------------------------------------------------------------------
//
// 当前提交（Task 3）覆盖：
//   - 平台门控（kIsWeb && Platform.isMacOS 双重保护）
//   - MethodChannel 注册（Wave 3 Task 6 才会真正实现 onMenuAction 分派）
//   - 偏好恢复（SharedPreferences → setEnabled 注入到 Swift）
//   - Provider 出口
//
// 预留方法 _subscribeToPlayer / _pushIfChanged / _onMethodCall / setEnabled
// 在 Wave 3 中实装；当前实现允许 build() 完整跑通，且非 macOS 平台无任何副作用。

class MacosStatusBarController extends Notifier<MacosStatusBarState> {
  // ---------------- 私有字段（Wave 1 ~ Wave 3 共享） ----------------

  /// MethodChannel 实例。仅在 macOS 平台上注册 handler。
  static const MethodChannel _channel = MethodChannel(kMacosStatusBarChannel);

  /// 标记本生命周期内是否已经因 channel 调用失败打过日志，
  /// 避免每 500ms 一次的日志洪水（设计文档 Error Handling 要求）。
  /// 在 `_pushIfChanged` 首次失败时被置为 true。
  bool _hasLoggedPushError = false;

  /// 静态平台门控：非 macOS（含 Web）平台一律视作禁用。
  static bool _isMacosPlatform() => !kIsWeb && Platform.isMacOS;

  // ---------------- Notifier 生命周期 ----------------

  @override
  MacosStatusBarState build() {
    if (!_isMacosPlatform()) {
      // 非 macOS：不注册 channel handler、不订阅 playerProvider、
      // 不读取 SharedPreferences。Provider 暴露的 enabled 恒为 false。
      return const MacosStatusBarState(enabled: false);
    }

    // macOS：
    //   1. 注册反向 channel handler（Task 6 完成时实装；当前留空 handler 占位）
    //   2. 异步恢复偏好；恢复后会调用 setEnabled() 把状态注入到 Swift
    //   3. 订阅 playerProvider（Task 4 实装）
    //   4. 注册 dispose 兜底，向 Swift 发 dispose（Task 5 实装）
    _channel.setMethodCallHandler(_onMethodCall);

    // 异步恢复偏好与初始化原生 UI：不能在 build() 中直接 await，
    // 这里只触发，不阻塞 Notifier 初始化。
    // ignore: discarded_futures
    _restorePreferenceAndInit();

    _subscribeToPlayer();

    ref.onDispose(_dispose);

    // 默认值：true。真实值会在 _restorePreferenceAndInit() 异步覆盖。
    // 当 SharedPreferences 中缺失键时也保持 true（R5.4）。
    return const MacosStatusBarState(enabled: true);
  }

  // ---------------- Task 3：偏好恢复 ----------------

  /// 异步：从 SharedPreferences 读取启用状态，并通知 Swift 端做一次 setEnabled。
  /// 任何异常均吞掉，缺省视作启用（R5.4、R6.1）。
  Future<void> _restorePreferenceAndInit() async {
    bool restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      // 当 key 不存在时返回 null，按 R5.4 视作 true
      final stored = prefs.getBool(kStatusBarLyricsEnabledPrefKey);
      if (stored != null) {
        restored = stored;
      }
    } catch (e) {
      // ignore: avoid_print
      print('[StatusBarLyrics] read prefs failed: $e');
    }

    // 用 setEnabled 推到 Swift；这里不直接修改 state，setEnabled 内部会做。
    try {
      await setEnabled(restored);
    } catch (e) {
      // ignore: avoid_print
      print('[StatusBarLyrics] init setEnabled failed: $e');
    }
  }

  // ---------------- Task 6：反向 handler ----------------

  /// 处理 Swift → Dart 的 channel 调用，目前唯一支持 `onMenuAction`。
  ///
  /// 整个 handler 用 try/catch 包住，确保异常不会回传给 Swift（避免对端
  /// 收到 FlutterError），符合设计文档的「异常不跨语言传播」约束。
  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method != 'onMenuAction') {
      return null;
    }
    try {
      final action = call.arguments;
      if (action is! String) return null;
      switch (action) {
        case 'togglePlayPause':
          ref.read(playerProvider.notifier).togglePlayPause();
          break;
        case 'previous':
          ref.read(playerProvider.notifier).previous();
          break;
        case 'next':
          ref.read(playerProvider.notifier).next();
          break;
        case 'closeStatusBar':
          // Swift 端已经立即 tearDown 了 UI，这里持久化 + 同步 Dart 状态。
          await setEnabled(false);
          break;
        default:
          // 未知 action：忽略
          break;
      }
    } catch (e) {
      // ignore: avoid_print
      print('[StatusBarLyrics] dispatch failed: $e');
    }
    return null;
  }

  // ---------------- Task 4：订阅播放器 ----------------

  /// 订阅 `playerProvider`：每次状态变化时计算菜单栏标题并推送给 Swift。
  ///
  /// 节奏：复用现有 `PlayerNotifier._positionTimer`（500ms）。每次 tick 都
  /// 会让 `playerProvider` 的 state 改变（至少 `position` 变了），
  /// 因此本回调自然以 500ms 为周期被触发。
  ///
  /// 切歌即时刷新（R3.8）：当 `currentSong.filePath` 发生变化时强制推送
  /// 一次，旁路掉 `_pushIfChanged` 的去重逻辑。
  void _subscribeToPlayer() {
    ref.listen<PlayerState>(playerProvider, (prev, next) {
      // 禁用态吞掉一切推送（R6.4 / Property 5）
      if (!state.enabled) return;

      final prevPath = prev?.currentSong?.filePath;
      final nextPath = next.currentSong?.filePath;
      final songSwitched = prevPath != nextPath;

      // 切歌：旁路去重，强制推送
      // 否则：常规节流去重
      // ignore: discarded_futures
      _pushIfChanged(next, force: songSwitched);
    });
  }

  /// 计算当前应当显示的标题，与 `state.lastPushedTitle` 比对去重，
  /// 若发生变化（或 `force == true`）则向 Swift 推送一次 `setText`。
  ///
  /// 异常隔离（Property 7）：channel 调用失败仅打印首次错误日志，
  /// 不向上抛、不影响 PlayerNotifier 的 _positionTimer 与 state.position。
  Future<void> _pushIfChanged(PlayerState s, {bool force = false}) async {
    if (!_isMacosPlatform()) return;
    if (!state.enabled) return;

    final title = computeStatusBarTitle(s);
    if (!force && title == state.lastPushedTitle) {
      return; // 去重：标题未变化（R3.3 / Property 3）
    }

    try {
      await _channel.invokeMethod<void>('setText', title);
      state = state.copyWith(lastPushedTitle: title);
    } catch (e) {
      if (!_hasLoggedPushError) {
        _hasLoggedPushError = true;
        // ignore: avoid_print
        print('[StatusBarLyrics] setText failed: $e (subsequent errors suppressed)');
      }
      // 不重新抛出；不污染 lastPushedTitle，下次还会重试
    }
  }

  // ---------------- Task 5：完整版 setEnabled ----------------

  /// 设置启用状态：
  ///   1. 持久化到 SharedPreferences
  ///   2. 更新 Notifier state（同时清空 lastPushedTitle，避免下次启用后
  ///      因为字符串恰好相同而漏掉首次推送）
  ///   3. 通知 Swift `setEnabled` 创建/移除 NSStatusItem
  ///   4. value == true 时，立即推送一次当前歌词（Property 6）
  ///
  /// 已包 try/catch：channel / prefs 异常都不会向上抛（Property 7）。
  Future<void> setEnabled(bool value) async {
    if (!_isMacosPlatform()) return;

    // 1) 持久化
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kStatusBarLyricsEnabledPrefKey, value);
    } catch (e) {
      // ignore: avoid_print
      print('[StatusBarLyrics] write prefs failed: $e');
    }

    // 2) 更新本地 state；禁用时清空 lastPushedTitle，避免下次启用后误判去重
    state = state.copyWith(
      enabled: value,
      clearLastPushedTitle: !value,
    );

    // 3) 通知 Swift
    try {
      await _channel.invokeMethod<void>('setEnabled', value);
    } catch (e) {
      // ignore: avoid_print
      print('[StatusBarLyrics] invoke setEnabled failed: $e');
    }

    // 4) 启用瞬间立即推送一次当前歌词（Property 6）
    if (value) {
      try {
        final current = ref.read(playerProvider);
        await _pushIfChanged(current, force: true);
      } catch (e) {
        // ignore: avoid_print
        print('[StatusBarLyrics] initial push failed: $e');
      }
    }
  }

  /// 向 Swift 主动发 dispose 信号。
  /// Provider 销毁时调用（理论上不会发生，仅做兜底）。
  Future<void> _dispose() async {
    if (!_isMacosPlatform()) return;
    try {
      await _channel.invokeMethod<void>('dispose');
    } catch (_) {
      // 静默吞
    }
  }
}

/// macOS 菜单栏歌词控制器的全局 Provider。
final macosStatusBarControllerProvider =
    NotifierProvider<MacosStatusBarController, MacosStatusBarState>(
      MacosStatusBarController.new,
    );
