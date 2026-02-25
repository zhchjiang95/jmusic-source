import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';

/// 歌词滚动显示组件
class LyricsView extends ConsumerStatefulWidget {
  /// 是否为全屏模式（隐藏顶部拖拽条和标题）
  final bool isFullScreen;

  const LyricsView({super.key, this.isFullScreen = false});

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  static const double _itemHeight = 48.0;
  int _lastLineIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动到指定歌词行
  void _scrollToLine(int index, int totalLines) {
    if (!_scrollController.hasClients || index < 0) return;

    // ListView 有 padding，内容区从 padding.top 开始
    // maxScrollExtent 已包含 padding 的影响
    // index * _itemHeight 是该行相对于内容区顶部的偏移
    // 加上顶部 padding 后再减半个视口使其居中
    final topPadding = _scrollController.position.maxScrollExtent > 0
        ? (_scrollController.position.maxScrollExtent -
                  (totalLines * _itemHeight -
                      _scrollController.position.viewportDimension)) /
              2
        : 0.0;
    final viewportHeight = _scrollController.position.viewportDimension;
    final targetOffset =
        (topPadding +
                index * _itemHeight -
                viewportHeight / 2 +
                _itemHeight / 2)
            .clamp(0.0, _scrollController.position.maxScrollExtent);

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = ref.watch(playerProvider.select((s) => s.lyrics));
    final currentMs = ref.watch(
      playerProvider.select((s) => s.position.inMilliseconds),
    );
    final theme = Theme.of(context);

    if (lyrics == null || lyrics.lines.isEmpty) {
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

    // 找到当前歌词行索引
    int currentLineIndex = -1;
    for (int i = lyrics.lines.length - 1; i >= 0; i--) {
      if (lyrics.lines[i].timeMs.toInt() <= currentMs) {
        currentLineIndex = i;
        break;
      }
    }

    // 当歌词行变化时自动滚动
    if (currentLineIndex != _lastLineIndex && currentLineIndex >= 0) {
      _lastLineIndex = currentLineIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToLine(currentLineIndex, lyrics.lines.length);
      });
    }

    return Column(
      children: [
        // 顶部拖拽指示器和标题（非全屏模式时显示）
        if (!widget.isFullScreen) ...[
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
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
        ],
        // 歌词列表（隐藏滚动条）
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 全屏模式时，上下留半个视口高度，使首尾行也能居中
                final verticalPad = widget.isFullScreen
                    ? constraints.maxHeight / 2 - _itemHeight / 2
                    : 8.0;
                return ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: verticalPad,
                  ),
                  itemCount: lyrics.lines.length,
                  itemExtent: _itemHeight,
                  itemBuilder: (context, index) {
                    final line = lyrics.lines[index];
                    final isCurrentLine = index == currentLineIndex;

                    return AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: TextStyle(
                        fontSize: isCurrentLine
                            ? (widget.isFullScreen ? 20 : 18)
                            : (widget.isFullScreen ? 16 : 15),
                        fontWeight: isCurrentLine
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isCurrentLine
                            ? theme.colorScheme.primary
                            : Colors.white.withValues(alpha: 0.35),
                        height: 1.5,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          line.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
