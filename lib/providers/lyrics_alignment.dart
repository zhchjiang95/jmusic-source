import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 歌词对齐方式枚举
enum LyricsAlignment {
  /// 居左
  left,

  /// 居中
  center,

  /// 居右
  right,
}

/// 歌词对齐方式扩展
extension LyricsAlignmentX on LyricsAlignment {
  /// 显示文案
  String get label {
    switch (this) {
      case LyricsAlignment.left:
        return '居左';
      case LyricsAlignment.center:
        return '居中';
      case LyricsAlignment.right:
        return '居右';
    }
  }

  /// 对应图标
  IconData get icon {
    switch (this) {
      case LyricsAlignment.left:
        return Icons.format_align_left_rounded;
      case LyricsAlignment.center:
        return Icons.format_align_center_rounded;
      case LyricsAlignment.right:
        return Icons.format_align_right_rounded;
    }
  }

  /// 文本对齐
  TextAlign get textAlign {
    switch (this) {
      case LyricsAlignment.left:
        return TextAlign.left;
      case LyricsAlignment.center:
        return TextAlign.center;
      case LyricsAlignment.right:
        return TextAlign.right;
    }
  }

  /// 容器对齐
  Alignment get containerAlignment {
    switch (this) {
      case LyricsAlignment.left:
        return Alignment.centerLeft;
      case LyricsAlignment.center:
        return Alignment.center;
      case LyricsAlignment.right:
        return Alignment.centerRight;
    }
  }

  /// 弹性布局横轴对齐
  CrossAxisAlignment get crossAxisAlignment {
    switch (this) {
      case LyricsAlignment.left:
        return CrossAxisAlignment.start;
      case LyricsAlignment.center:
        return CrossAxisAlignment.center;
      case LyricsAlignment.right:
        return CrossAxisAlignment.end;
    }
  }

  String get prefValue => name;

  static LyricsAlignment fromPref(String? v) {
    switch (v) {
      case 'center':
        return LyricsAlignment.center;
      case 'right':
        return LyricsAlignment.right;
      default:
        return LyricsAlignment.left;
    }
  }
}

const String _kLyricsAlignmentPrefKey = 'lyrics_alignment';

/// 歌词对齐方式 Provider
final lyricsAlignmentProvider =
    NotifierProvider<LyricsAlignmentNotifier, LyricsAlignment>(
  LyricsAlignmentNotifier.new,
);

class LyricsAlignmentNotifier extends Notifier<LyricsAlignment> {
  @override
  LyricsAlignment build() {
    _restore();
    return LyricsAlignment.left;
  }

  void _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString(_kLyricsAlignmentPrefKey);
      state = LyricsAlignmentX.fromPref(val);
    } catch (_) {}
  }

  void setAlignment(LyricsAlignment alignment) async {
    state = alignment;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLyricsAlignmentPrefKey, alignment.prefValue);
    } catch (_) {}
  }

  /// 顺序切换对齐方式：居左 -> 居中 -> 居右 -> 居左
  void cycle() {
    switch (state) {
      case LyricsAlignment.left:
        setAlignment(LyricsAlignment.center);
        break;
      case LyricsAlignment.center:
        setAlignment(LyricsAlignment.right);
        break;
      case LyricsAlignment.right:
        setAlignment(LyricsAlignment.left);
        break;
    }
  }
}
