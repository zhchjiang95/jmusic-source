import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/widgets/lyrics_card.dart';

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
  List<GlobalKey> _keys = [];
  int _lastLineIndex = -1;
  Object? _lastLyrics;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动到指定歌词行
  void _scrollToLine(int index) {
    if (!_scrollController.hasClients || index < 0 || index >= _keys.length) return;
    
    final key = _keys[index];
    if (key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = ref.watch(playerProvider.select((s) => s.lyrics));
    final currentMs = ref.watch(
      playerProvider.select((s) => s.position.inMilliseconds),
    );
    final theme = Theme.of(context);

    // 当歌词对象发生变化时（例如切换歌曲），重置状态并滚动到顶部
    if (lyrics != _lastLyrics) {
      _lastLyrics = lyrics;
      _lastLineIndex = -1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }

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

    // 确保有足够的 GlobalKey
    if (_keys.length != lyrics.lines.length) {
      _keys = List.generate(lyrics.lines.length, (_) => GlobalKey());
    }

    // 当歌词行变化时自动滚动
    if (currentLineIndex != _lastLineIndex && currentLineIndex >= 0) {
      _lastLineIndex = currentLineIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToLine(currentLineIndex);
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
                    ? constraints.maxHeight / 2 - 24.0
                    : 8.0;
                return SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: verticalPad,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(lyrics.lines.length, (index) {
                      final line = lyrics.lines[index];
                      final isCurrentLine = index == currentLineIndex;

                      final lineWidget = Container(
                        key: _keys[index],
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        alignment: Alignment.centerLeft,
                        child: AnimatedDefaultTextStyle(
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
                          child: Text(
                            line.text,
                            textAlign: TextAlign.left,
                          ),
                        ),
                      );

                      // 全屏模式下长按歌词行可生成分享卡片
                      if (widget.isFullScreen && line.text.trim().isNotEmpty) {
                        return GestureDetector(
                          onLongPress: () {
                            final playerState = ref.read(playerProvider);
                            showLyricsCardDialog(
                              context,
                              lyricText: line.text,
                              songTitle:
                                  playerState.currentSong?.title ?? '未知歌曲',
                              artist:
                                  playerState.currentSong?.artist ?? '未知歌手',
                              album:
                                  playerState.currentSong?.album ?? '',
                              coverData: playerState.coverData,
                            );
                          },
                          child: lineWidget,
                        );
                      }

                      return lineWidget;
                    }),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
