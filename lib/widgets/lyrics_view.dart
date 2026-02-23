import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';

/// 歌词滚动显示组件
class LyricsView extends ConsumerWidget {
  const LyricsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerProvider);
    final theme = Theme.of(context);

    if (state.lyrics == null || state.lyrics!.lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 16,
          ),
        ),
      );
    }

    final lyrics = state.lyrics!;
    final currentMs = state.position.inMilliseconds;

    // 找到当前歌词行索引
    int currentLineIndex = -1;
    for (int i = lyrics.lines.length - 1; i >= 0; i--) {
      if (lyrics.lines[i].timeMs.toInt() <= currentMs) {
        currentLineIndex = i;
        break;
      }
    }

    return Column(
      children: [
        // 顶部拖拽指示器
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // 标题
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            '歌词',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 歌词列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            itemCount: lyrics.lines.length,
            itemBuilder: (context, index) {
              final line = lyrics.lines[index];
              final isCurrentLine = index == currentLineIndex;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(
                    fontSize: isCurrentLine ? 18 : 15,
                    fontWeight: isCurrentLine
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isCurrentLine
                        ? theme.colorScheme.primary
                        : Colors.white.withValues(alpha: 0.4),
                    height: 1.5,
                  ),
                  child: Text(line.text, textAlign: TextAlign.center),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
