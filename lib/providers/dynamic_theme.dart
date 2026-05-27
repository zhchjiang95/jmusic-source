import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';

/// 动态主题状态：从专辑封面提取的 ColorScheme
class DynamicThemeState {
  final ColorScheme? colorScheme;
  final bool isLoading;

  const DynamicThemeState({this.colorScheme, this.isLoading = false});

  DynamicThemeState copyWith({ColorScheme? colorScheme, bool? isLoading, bool clearScheme = false}) {
    return DynamicThemeState(
      colorScheme: clearScheme ? null : (colorScheme ?? this.colorScheme),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 动态主题 Notifier — 监听封面变化，提取主色生成 ColorScheme
class DynamicThemeNotifier extends Notifier<DynamicThemeState> {
  List<int>? _lastCoverData;

  @override
  DynamicThemeState build() {
    // 监听 playerProvider 的 coverData 变化
    ref.listen(
      playerProvider.select((s) => s.coverData),
      (prev, next) {
        _onCoverChanged(next);
      },
    );
    return const DynamicThemeState();
  }

  void _onCoverChanged(List<int>? coverData) async {
    // 封面没变就不重新提取
    if (identical(coverData, _lastCoverData)) return;
    _lastCoverData = coverData;

    if (coverData == null || coverData.isEmpty) {
      state = state.copyWith(clearScheme: true, isLoading: false);
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      final imageProvider = MemoryImage(Uint8List.fromList(coverData));
      final scheme = await ColorScheme.fromImageProvider(
        provider: imageProvider,
        brightness: Brightness.dark,
      );
      // 确保提取完成时封面没有再次变化
      if (identical(_lastCoverData, coverData)) {
        state = DynamicThemeState(colorScheme: scheme, isLoading: false);
      }
    } catch (_) {
      // 提取失败时回退到默认主题
      state = state.copyWith(clearScheme: true, isLoading: false);
    }
  }
}

/// 动态主题全局 Provider
final dynamicThemeProvider =
    NotifierProvider<DynamicThemeNotifier, DynamicThemeState>(
  DynamicThemeNotifier.new,
);

/// 默认 ColorScheme（无封面时使用）
ColorScheme defaultDarkScheme() => ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.dark,
    );

/// 根据动态主题状态构建完整 ThemeData
ThemeData buildTheme(ColorScheme scheme) {
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'System',
    scaffoldBackgroundColor: const Color(0xFF121212),
    cardTheme: const CardThemeData(color: Color(0xFF1E1E2E), elevation: 0),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}
