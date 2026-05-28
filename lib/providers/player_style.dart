import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放页视觉风格
enum PlayerVisualStyle {
  /// 默认：渐变背景 + 方形封面
  standard,

  /// 模糊背景：封面高斯模糊铺满背景
  blur,

  /// 黑胶唱片：CD 旋转 + 粒子效果
  vinyl,
}

extension PlayerVisualStyleX on PlayerVisualStyle {
  String get label {
    switch (this) {
      case PlayerVisualStyle.standard:
        return '标准';
      case PlayerVisualStyle.blur:
        return '模糊';
      case PlayerVisualStyle.vinyl:
        return '黑胶';
    }
  }

  String get prefValue => name;

  static PlayerVisualStyle fromPref(String? v) {
    switch (v) {
      case 'blur':
        return PlayerVisualStyle.blur;
      case 'vinyl':
        return PlayerVisualStyle.vinyl;
      default:
        return PlayerVisualStyle.standard;
    }
  }
}

const String _kPrefKey = 'player_visual_style';

/// 播放页风格 Provider
final playerVisualStyleProvider =
    NotifierProvider<PlayerVisualStyleNotifier, PlayerVisualStyle>(
  PlayerVisualStyleNotifier.new,
);

class PlayerVisualStyleNotifier extends Notifier<PlayerVisualStyle> {
  @override
  PlayerVisualStyle build() {
    _restore();
    return PlayerVisualStyle.standard;
  }

  void _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final style = PlayerVisualStyleX.fromPref(prefs.getString(_kPrefKey));
      state = style;
    } catch (_) {}
  }

  void setStyle(PlayerVisualStyle style) async {
    state = style;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefKey, style.prefValue);
    } catch (_) {}
  }

  void next() {
    final values = PlayerVisualStyle.values;
    final nextIdx = (state.index + 1) % values.length;
    setStyle(values[nextIdx]);
  }
}
