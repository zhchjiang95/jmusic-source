import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';

/// 睡前定时器状态
class SleepTimerState {
  /// 是否激活
  final bool isActive;

  /// 总时长（分钟）
  final int totalMinutes;

  /// 剩余秒数
  final int remainingSeconds;

  /// 渐弱时长（最后 N 秒开始降低音量）
  final int fadeSeconds;

  const SleepTimerState({
    this.isActive = false,
    this.totalMinutes = 30,
    this.remainingSeconds = 0,
    this.fadeSeconds = 60,
  });

  SleepTimerState copyWith({
    bool? isActive,
    int? totalMinutes,
    int? remainingSeconds,
    int? fadeSeconds,
  }) {
    return SleepTimerState(
      isActive: isActive ?? this.isActive,
      totalMinutes: totalMinutes ?? this.totalMinutes,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      fadeSeconds: fadeSeconds ?? this.fadeSeconds,
    );
  }

  /// 格式化剩余时间
  String get remainingFormatted {
    final m = remainingSeconds ~/ 60;
    final s = remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 当前是否处于渐弱阶段
  bool get isFading => isActive && remainingSeconds <= fadeSeconds;

  /// 渐弱进度（1.0 = 刚进入渐弱，0.0 = 即将停止）
  double get fadeProgress =>
      fadeSeconds > 0 ? (remainingSeconds / fadeSeconds).clamp(0.0, 1.0) : 1.0;
}

/// 睡前定时器 Provider
final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, SleepTimerState>(
  SleepTimerNotifier.new,
);

class SleepTimerNotifier extends Notifier<SleepTimerState> {
  Timer? _timer;
  double? _originalVolume;

  @override
  SleepTimerState build() {
    ref.onDispose(() {
      _timer?.cancel();
    });
    return const SleepTimerState();
  }

  /// 启动定时器
  void start({required int minutes, int fadeSeconds = 60}) {
    cancel(); // 先取消已有的

    final player = ref.read(playerProvider);
    _originalVolume = player.volume;

    state = SleepTimerState(
      isActive: true,
      totalMinutes: minutes,
      remainingSeconds: minutes * 60,
      fadeSeconds: fadeSeconds,
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// 取消定时器
  void cancel() {
    _timer?.cancel();
    _timer = null;

    // 恢复原始音量
    if (_originalVolume != null) {
      ref.read(playerProvider.notifier).setVolume(_originalVolume!);
      _originalVolume = null;
    }

    state = state.copyWith(isActive: false, remainingSeconds: 0);
  }

  /// 每秒 tick
  void _tick() {
    if (!state.isActive) return;

    final remaining = state.remainingSeconds - 1;

    if (remaining <= 0) {
      // 时间到，暂停播放
      ref.read(playerProvider.notifier).togglePlayPause();
      cancel();
      return;
    }

    state = state.copyWith(remainingSeconds: remaining);

    // 渐弱阶段：逐步降低音量
    if (remaining <= state.fadeSeconds && _originalVolume != null) {
      final progress = remaining / state.fadeSeconds; // 1.0 → 0.0
      final vol = _originalVolume! * progress;
      ref.read(playerProvider.notifier).setVolume(vol.clamp(0.0, 1.0));
    }
  }

  /// 增加时间（+5 分钟）
  void addMinutes(int minutes) {
    if (!state.isActive) return;
    state = state.copyWith(
      remainingSeconds: state.remainingSeconds + minutes * 60,
    );
  }
}
