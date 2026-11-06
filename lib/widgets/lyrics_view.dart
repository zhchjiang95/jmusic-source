import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/pages/lyrics_editor_page.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/providers/lyrics_alignment.dart';
import 'package:jmusic/widgets/karaoke_lyric_line.dart';
import 'package:jmusic/widgets/lyrics_card.dart';

/// 卡拉OK逐字渐变与层次透明度歌词视图
///
/// 核心特性：
/// 1. 完整歌词流展示，当前演唱行支持 60/120FPS 逐字流光渐变（无逐字数据时平滑降级整行高亮），无多余背景框与边框。
/// 2. 空间层次透明度：非当前行按距离阶梯式递减透明度（清晰不模糊），字号饱满易读。
/// 3. 直觉式寻轨交互：鼠标悬停任意歌词行显示微光底色与时间戳徽章，点击直接跳转至该句时间播放；长按生成分享卡片。
/// 4. 顶部与底部边缘柔和羽化消融遮罩（ShaderMask），滚动进出视野自然过渡。
/// 5. 手动滚轮浏览防抢占：用户手动滚动时暂停自动居中 3 秒，随后平滑恢复追踪当前演唱行。
class LyricsView extends ConsumerStatefulWidget {
  /// 是否为全屏/内嵌无标题模式
  final bool isFullScreen;

  /// 是否处于纯享全屏展开态（字号进一步放大）
  final bool isExpandedStage;

  /// 全局操作控件是否处于可见态（静止隐藏时同步隐藏光标与悬停胶囊）
  final bool controlsVisible;

  /// 点击“搜索歌词”时的回调（由父页面触发搜索渠道面板）
  final VoidCallback? onSearchLyrics;

  const LyricsView({
    super.key,
    this.isFullScreen = true,
    this.isExpandedStage = false,
    this.controlsVisible = true,
    this.onSearchLyrics,
  });

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  List<GlobalKey> _keys = [];
  int _lastLineIndex = -1;
  Object? _lastLyrics;

  /// 鼠标是否悬停在歌词区域内
  bool _isPointerInArea = false;

  /// 当前鼠标悬停的具体歌词行索引
  int? _hoveredLineIndex;

  /// 用户是否正在手动滚动歌词（手动滚动期间暂时挂起自动滚回）
  bool _isUserScrolling = false;
  Timer? _userScrollResumeTimer;

  @override
  void dispose() {
    _userScrollResumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// 标记用户手动滚动，3 秒无滚动后自动恢复歌词追踪
  void _onUserScrollActivity() {
    if (!_isUserScrolling) {
      setState(() {
        _isUserScrolling = true;
      });
    }
    _userScrollResumeTimer?.cancel();
    _userScrollResumeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isUserScrolling = false;
        });
        if (_lastLineIndex >= 0) {
          _scrollToLine(_lastLineIndex);
        }
      }
    });
  }

  /// 平滑滚动到指定歌词行（置于黄金视觉中心偏上 0.42 处）
  void _scrollToLine(int index) {
    if (!_scrollController.hasClients || index < 0 || index >= _keys.length) {
      return;
    }

    final key = _keys[index];
    if (key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        alignment: 0.42,
      );
    }
  }

  /// 格式化毫秒时间戳为 mm:ss
  String _formatTimestamp(int ms) {
    final totalSeconds = (ms ~/ 1000).clamp(0, 359999);
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = ref.watch(playerProvider.select((s) => s.lyrics));
    final currentMs = ref.watch(
      playerProvider.select((s) => s.position.inMilliseconds),
    );
    final alignment = ref.watch(lyricsAlignmentProvider);
    final theme = Theme.of(context);

    // 当歌词对象发生变化时（例如切换歌曲），重置状态并滚动到顶部
    if (lyrics != _lastLyrics) {
      _lastLyrics = lyrics;
      _lastLineIndex = -1;
      _hoveredLineIndex = null;
      _isUserScrolling = false;
      _userScrollResumeTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }

    if (lyrics == null || lyrics.lines.isEmpty) {
      return _buildEmptyLyricsState(context, theme);
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

    // 当歌词行变化且用户未在手动滚动时，自动平滑滚动到当前行
    if (currentLineIndex != _lastLineIndex && currentLineIndex >= 0) {
      _lastLineIndex = currentLineIndex;
      if (!_isUserScrolling) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToLine(currentLineIndex);
        });
      }
    }

    return Column(
      children: [
        // 顶部拖拽指示器和标题（仅在底部抽屉等非全屏模式下显示）
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

        // 主体歌词流（带上下边缘羽化消融遮罩）
        Expanded(
          child: MouseRegion(
            onEnter: (_) => setState(() => _isPointerInArea = true),
            onExit: (_) => setState(() {
              _isPointerInArea = false;
              _hoveredLineIndex = null;
            }),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (Rect rect) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.08, 0.88, 1.0],
                ).createShader(rect);
              },
              child: NotificationListener<UserScrollNotification>(
                onNotification: (notification) {
                  _onUserScrollActivity();
                  return false;
                },
                child: Listener(
                  onPointerSignal: (_) => _onUserScrollActivity(),
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      scrollbars: false,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // 上下预留充足视口空间，确保第一行与最后一行也能滚动到黄金中心位
                        final verticalPad = widget.isFullScreen
                            ? (constraints.maxHeight * 0.42).clamp(60.0, 320.0)
                            : 16.0;
                        final horizontalPad = widget.isExpandedStage
                            ? (constraints.maxWidth * 0.12).clamp(32.0, 140.0)
                            : 16.0;

                        return SingleChildScrollView(
                          controller: _scrollController,
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPad,
                            vertical: verticalPad,
                          ),
                          child: Column(
                            crossAxisAlignment: alignment.crossAxisAlignment,
                            children: List.generate(lyrics.lines.length, (index) {
                              return _buildSpatialLyricItem(
                                context: context,
                                theme: theme,
                                alignment: alignment,
                                index: index,
                                currentLineIndex: currentLineIndex,
                                currentMs: currentMs,
                                line: lyrics.lines[index],
                              );
                            }),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建具备层次透明度衰减、悬停寻轨与逐字染色的单行歌词项（无突兀背景与边框，清晰不模糊）
  Widget _buildSpatialLyricItem({
    required BuildContext context,
    required ThemeData theme,
    required LyricsAlignment alignment,
    required int index,
    required int currentLineIndex,
    required int currentMs,
    required dynamic line,
  }) {
    final isCurrentLine = index == currentLineIndex;
    final isHovered = widget.controlsVisible && index == _hoveredLineIndex;
    final distance = currentLineIndex >= 0
        ? (index - currentLineIndex).abs()
        : index;

    // 计算距离层次透明度（不做模糊，仅通过透明度营造空间呼吸层次）
    final double inactiveAlpha;
    if (isCurrentLine) {
      inactiveAlpha = 0.42; // 当前行中尚未唱到的字底色
    } else if (isHovered) {
      inactiveAlpha = 0.92;
    } else if (widget.controlsVisible &&
        (_isPointerInArea || _isUserScrolling)) {
      inactiveAlpha = distance == 1
          ? 0.68
          : (distance == 2 ? 0.54 : 0.40);
    } else {
      if (distance == 1) {
        inactiveAlpha = 0.58;
      } else if (distance == 2) {
        inactiveAlpha = 0.42;
      } else if (distance == 3) {
        inactiveAlpha = 0.30;
      } else {
        inactiveAlpha = 0.22;
      }
    }

    // 字号：增大非当前行字号，使整体歌词饱满大气
    final double activeFontSize = widget.isExpandedStage ? 33.0 : 28.0;
    final double normalFontSize = widget.isExpandedStage ? 24.0 : 21.0;

    final lyricContent = KaraokeLyricLine(
      line: line,
      currentMs: currentMs,
      isCurrentLine: isCurrentLine,
      textAlign: alignment.textAlign,
      textStyle: TextStyle(
        fontSize: isCurrentLine ? activeFontSize : normalFontSize,
        fontWeight: isCurrentLine
            ? FontWeight.w800
            : (isHovered ? FontWeight.w600 : FontWeight.w500),
        height: 1.48,
        letterSpacing: isCurrentLine ? 0.3 : 0.15,
      ),
      activeColor: theme.colorScheme.primary,
      inactiveColor: isCurrentLine
          ? Colors.white.withValues(alpha: 0.42)
          : Colors.white.withValues(alpha: inactiveAlpha),
    );

    return MouseRegion(
      cursor: widget.controlsVisible
          ? SystemMouseCursors.click
          : SystemMouseCursors.none,
      onEnter: (_) => setState(() => _hoveredLineIndex = index),
      onExit: (_) {
        if (_hoveredLineIndex == index) {
          setState(() => _hoveredLineIndex = null);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // 点击任意歌词行直接跳转至该句起始时间播放
          final targetMs = line.timeMs.toInt();
          final notifier = ref.read(playerProvider.notifier);
          notifier.seekTo(Duration(milliseconds: targetMs));
          if (!ref.read(playerProvider).isPlaying) {
            notifier.togglePlayPause();
          }
          setState(() {
            _isUserScrolling = false;
          });
        },
        onLongPress: line.text.trim().isNotEmpty
            ? () {
                final playerState = ref.read(playerProvider);
                showLyricsCardDialog(
                  context,
                  lyricText: line.text,
                  songTitle: playerState.currentSong?.title ?? '未知歌曲',
                  artist: playerState.currentSong?.artist ?? '未知歌手',
                  album: playerState.currentSong?.album ?? '',
                  coverData: playerState.coverData,
                );
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          key: _keys[index],
          width: double.infinity,
          margin: EdgeInsets.symmetric(
            vertical: isCurrentLine ? 6.0 : 2.0,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 12.0,
            vertical: isCurrentLine ? 12.0 : 10.0,
          ),
          // 当前歌词不加边框和背景，仅在鼠标主动悬停某一行时给出极轻量底色反馈
          decoration: BoxDecoration(
            color: isHovered
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: switch (alignment) {
              LyricsAlignment.left => MainAxisAlignment.start,
              LyricsAlignment.center => MainAxisAlignment.center,
              LyricsAlignment.right => MainAxisAlignment.end,
            },
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 歌词文字主体
              Expanded(
                child: Align(
                  alignment: alignment.containerAlignment,
                  child: lyricContent,
                ),
              ),

              // 鼠标悬停时浮现的快捷时间跳转胶囊
              if (isHovered) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.45),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 13,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _formatTimestamp(line.timeMs.toInt()),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 无歌词时的先锋毛玻璃引导卡片
  Widget _buildEmptyLyricsState(BuildContext context, ThemeData theme) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.14),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: Icon(
                Icons.lyrics_rounded,
                size: 28,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '当前曲目暂无歌词',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '可在线搜索 LRC 歌词，或进入编辑器手动导入并制作卡拉OK逐字时间戳',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                if (widget.onSearchLyrics != null)
                  FilledButton.tonalIcon(
                    onPressed: widget.onSearchLyrics,
                    icon: const Icon(Icons.travel_explore_rounded, size: 16),
                    label: const Text('搜索在线歌词'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LyricsEditorPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('打开歌词编辑器'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
