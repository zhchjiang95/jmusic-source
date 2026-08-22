import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:jmusic/providers/app_providers.dart';

/// 平台屏幕常亮接口抽象（便于测试与跨平台适配）
abstract class WakelockPlatformHandler {
  Future<void> enable();
  Future<void> disable();
}

/// 默认的 WakelockPlus 平台处理器
class DefaultWakelockPlatformHandler implements WakelockPlatformHandler {
  const DefaultWakelockPlatformHandler();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

/// 平台处理器 Provider（单元测试可 override）
final wakelockPlatformHandlerProvider =
    Provider<WakelockPlatformHandler>((ref) {
  return const DefaultWakelockPlatformHandler();
});

/// 屏幕常亮状态
class WakelockState {
  /// 当前请求常亮的活跃页面/组件数
  final int activeCount;

  /// 当前系统屏幕常亮是否已激活
  final bool isAwake;

  const WakelockState({
    this.activeCount = 0,
    this.isAwake = false,
  });

  WakelockState copyWith({
    int? activeCount,
    bool? isAwake,
  }) {
    return WakelockState(
      activeCount: activeCount ?? this.activeCount,
      isAwake: isAwake ?? this.isAwake,
    );
  }
}

/// 屏幕常亮管理 Provider
final wakelockProvider =
    NotifierProvider<WakelockNotifier, WakelockState>(
  WakelockNotifier.new,
);

/// 屏幕常亮控制器
class WakelockNotifier extends Notifier<WakelockState> {
  WakelockPlatformHandler? _handler;

  WakelockPlatformHandler get _effectiveHandler =>
      _handler ?? const DefaultWakelockPlatformHandler();

  @override
  WakelockState build() {
    _handler = ref.read(wakelockPlatformHandlerProvider);

    // 监听播放器播放状态变化
    ref.listen<bool>(
      playerProvider.select((s) => s.isPlaying),
      (prev, isPlaying) {
        _syncWakelock(isPlaying: isPlaying);
      },
    );

    ref.onDispose(() {
      _handler?.disable().catchError((e) {
        debugPrint('[Wakelock] onDispose 停用常亮失败: $e');
      });
    });

    return const WakelockState();
  }

  /// 页面或组件进入活跃状态，申请常亮引用
  void acquire() {
    state = state.copyWith(activeCount: state.activeCount + 1);
    _syncWakelock();
  }

  /// 页面或组件退出活跃状态，释放常亮引用
  void release() {
    final newCount = (state.activeCount - 1).clamp(0, 9999);
    state = state.copyWith(activeCount: newCount);
    _syncWakelock();
  }

  /// 同步常亮状态：仅在有活跃页面且处于播放状态时开启常亮
  Future<void> _syncWakelock({bool? isPlaying}) async {
    final playing = isPlaying ?? ref.read(playerProvider).isPlaying;
    final shouldBeAwake = state.activeCount > 0 && playing;

    if (state.isAwake == shouldBeAwake) return;

    state = state.copyWith(isAwake: shouldBeAwake);
    if (shouldBeAwake) {
      await _enableWakelock();
    } else {
      await _disableWakelock();
    }
  }

  Future<void> _enableWakelock() async {
    try {
      await _effectiveHandler.enable();
    } catch (e) {
      debugPrint('[Wakelock] 启用屏幕常亮失败: $e');
    }
  }

  Future<void> _disableWakelock() async {
    try {
      await _effectiveHandler.disable();
    } catch (e) {
      debugPrint('[Wakelock] 停用屏幕常亮失败: $e');
    }
  }
}

/// 保持屏幕常亮包装组件
/// 在该组件生命周期内（挂载到卸载），配合播放状态自动维持屏幕常亮
class KeepScreenAwake extends ConsumerStatefulWidget {
  final Widget child;

  const KeepScreenAwake({super.key, required this.child});

  @override
  ConsumerState<KeepScreenAwake> createState() => _KeepScreenAwakeState();
}

class _KeepScreenAwakeState extends ConsumerState<KeepScreenAwake> {
  WakelockNotifier? _notifier;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        _notifier = ref.read(wakelockProvider.notifier);
        _notifier?.acquire();
      }
    });
  }

  @override
  void dispose() {
    final notifier = _notifier;
    if (notifier != null) {
      Future.microtask(() {
        notifier.release();
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
