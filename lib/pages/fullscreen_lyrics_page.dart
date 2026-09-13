import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/providers/wakelock_provider.dart';
import 'package:jmusic/src/rust/models/song.dart';
import 'package:jmusic/widgets/lyrics_view.dart';
import 'package:jmusic/widgets/spectrum_view.dart';

/// 沉浸式全屏歌词页面
///
/// 特性：
/// 1. 顶部返回信息与歌曲标题水平居中悬浮胶囊展示，完全避免与 macOS 交通灯冲突；
/// 2. 底部控制条悬浮展示；
/// 3. 歌词层铺满整个屏幕底层，当顶部和底部控制层自动隐藏时，原本被遮挡的上下歌词可完整展现；
/// 4. 鼠标在页面移动时唤醒控制栏，静止 3 秒或移出窗口后平滑淡出隐藏，并隐藏鼠标光标。
class FullscreenLyricsPage extends ConsumerStatefulWidget {
  final Song? currentSong;

  const FullscreenLyricsPage({
    super.key,
    this.currentSong,
  });

  @override
  ConsumerState<FullscreenLyricsPage> createState() =>
      _FullscreenLyricsPageState();
}

class _FullscreenLyricsPageState extends ConsumerState<FullscreenLyricsPage> {
  /// 控制栏是否可见
  bool _controlsVisible = true;

  /// 自动隐藏计时器
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  /// 开启/重置 3 秒无操作自动隐藏计时器
  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controlsVisible) {
        setState(() {
          _controlsVisible = false;
        });
      }
    });
  }

  /// 鼠标在页面内移动或移入时恢复显示
  void _onPointerMove() {
    if (!_controlsVisible) {
      setState(() {
        _controlsVisible = true;
      });
    }
    _startHideTimer();
  }

  /// 鼠标移出窗口时立即隐藏控制栏
  void _onPointerExit() {
    _hideTimer?.cancel();
    if (mounted && _controlsVisible) {
      setState(() {
        _controlsVisible = false;
      });
    }
  }

  /// 点击屏幕切换控制栏显隐
  void _toggleControlsVisibility() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    if (_controlsVisible) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifier = ref.read(playerProvider.notifier);
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final song = ref.watch(playerProvider.select((s) => s.currentSong)) ??
        widget.currentSong;

    return KeepScreenAwake(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): () =>
              notifier.togglePlayPause(),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              notifier.next(),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              notifier.previous(),
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).pop(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: const Color(0xFF121212),
            body: MouseRegion(
              cursor: _controlsVisible
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.none,
              onEnter: (_) => _onPointerMove(),
              onHover: (_) => _onPointerMove(),
              onExit: (_) => _onPointerExit(),
              child: GestureDetector(
                onTap: _toggleControlsVisibility,
                behavior: HitTestBehavior.translucent,
                child: Stack(
                  children: [
                    // 1. 动态渐变背景
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              theme.colorScheme.primary
                                  .withValues(alpha: 0.22),
                              const Color(0xFF121212),
                              const Color(0xFF0D0D0D),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 2. 频谱背景（带柔和径向遮罩）
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (rect) => const RadialGradient(
                            center: Alignment.center,
                            radius: 0.9,
                            colors: [Colors.white, Colors.transparent],
                            stops: [0.55, 1.0],
                          ).createShader(rect),
                          child: Consumer(
                            builder: (context, ref, _) {
                              final spec = ref.watch(
                                playerProvider.select((s) => s.spectrum),
                              );
                              return SpectrumView(
                                spectrum: spec,
                                opacity: 0.25,
                              );
                            },
                          ),
                        ),
                      ),
                    ),

                    // 3. 歌词层（铺满整屏，隐藏控制层时完整展示所有行）
                    const Positioned.fill(
                      child: LyricsView(isFullScreen: true),
                    ),

                    // 4. 顶部水平居中悬浮返回与歌曲信息栏
                    Positioned(
                      top: Platform.isMacOS ? 16.0 : 12.0,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: AnimatedSlide(
                          offset: _controlsVisible
                              ? Offset.zero
                              : const Offset(0, -0.6),
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeInOutCubic,
                          child: AnimatedOpacity(
                            opacity: _controlsVisible ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeInOutCubic,
                            child: IgnorePointer(
                              ignoring: !_controlsVisible,
                              child: _buildCenterHeader(context, song),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 5. 底部水平居中悬浮播放控制栏
                    Positioned(
                      bottom: 24.0,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: AnimatedSlide(
                          offset: _controlsVisible
                              ? Offset.zero
                              : const Offset(0, 0.6),
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeInOutCubic,
                          child: AnimatedOpacity(
                            opacity: _controlsVisible ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeInOutCubic,
                            child: IgnorePointer(
                              ignoring: !_controlsVisible,
                              child: _buildCenterControls(
                                  context, ref, isPlaying, theme),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建顶部水平居中信息胶囊（返回按钮 + 歌曲名与歌手）
  Widget _buildCenterHeader(BuildContext context, Song? song) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 返回按钮
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white,
              size: 24,
            ),
            tooltip: '返回播放页 (Esc)',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              hoverColor: Colors.white.withValues(alpha: 0.18),
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(6),
              minimumSize: const Size(32, 32),
            ),
          ),
          const SizedBox(width: 10),
          // 垂直微细分割线
          Container(
            width: 1,
            height: 18,
            color: Colors.white.withValues(alpha: 0.18),
          ),
          const SizedBox(width: 12),
          // 居中显示的歌曲标题与歌手
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  song?.title ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (song != null && song.artist.isNotEmpty)
                  Text(
                    song.artist,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// 构建底部水平居中播放控制胶囊
  Widget _buildCenterControls(
    BuildContext context,
    WidgetRef ref,
    bool isPlaying,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 上一首
          IconButton(
            onPressed: () => ref.read(playerProvider.notifier).previous(),
            icon: const Icon(
              Icons.skip_previous_rounded,
              color: Colors.white70,
              size: 28,
            ),
            tooltip: '上一首',
          ),
          const SizedBox(width: 12),
          // 播放 / 暂停
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              onPressed: () =>
                  ref.read(playerProvider.notifier).togglePlayPause(),
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 26,
              ),
              tooltip: isPlaying ? '暂停 (空格)' : '播放 (空格)',
            ),
          ),
          const SizedBox(width: 12),
          // 下一首
          IconButton(
            onPressed: () => ref.read(playerProvider.notifier).next(),
            icon: const Icon(
              Icons.skip_next_rounded,
              color: Colors.white70,
              size: 28,
            ),
            tooltip: '下一首',
          ),
        ],
      ),
    );
  }
}
