import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/src/rust/api/player.dart' as rust_player;

/// 播放速度 Provider
final playbackSpeedProvider =
    NotifierProvider<PlaybackSpeedNotifier, double>(PlaybackSpeedNotifier.new);

class PlaybackSpeedNotifier extends Notifier<double> {
  static const _channel = MethodChannel('com.jmusic.app/player');

  @override
  double build() {
    return 1.0;
  }

  /// 设置播放速度（0.5 ~ 2.0）
  void setSpeed(double speed) {
    final clamped = speed.clamp(0.5, 2.0);
    state = clamped;
    _applySpeed(clamped);
  }

  /// 重置为 1.0x
  void reset() {
    state = 1.0;
    _applySpeed(1.0);
  }

  void _applySpeed(double speed) {
    try {
      if (Platform.isAndroid) {
        _channel.invokeMethod('setSpeed', speed.toString());
      } else {
        rust_player.playerSetSpeed(speed: speed);
      }
    } catch (_) {}
  }
}
