import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/providers/playback_speed.dart';
import 'package:jmusic/providers/player_style.dart';
import 'package:jmusic/providers/sleep_timer.dart';
import 'package:jmusic/pages/lyrics_editor_page.dart';
import 'package:jmusic/widgets/lyrics_view.dart';
import 'package:jmusic/widgets/particles_bg.dart';
import 'package:jmusic/widgets/sleep_timer_sheet.dart';
import 'package:jmusic/widgets/speed_control_sheet.dart';
import 'package:jmusic/widgets/spectrum_view.dart';
import 'package:jmusic/widgets/vinyl_disc.dart';

/// 全屏播放页面
class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final playMode = ref.watch(playerProvider.select((s) => s.playMode));
    final volume = ref.watch(playerProvider.select((s) => s.volume));
    final visualStyle = ref.watch(playerVisualStyleProvider);
    final theme = Theme.of(context);
    final notifier = ref.read(playerProvider.notifier);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () =>
            notifier.togglePlayPause(),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            notifier.next(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            notifier.previous(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Stack(
            children: [
              // 背景层
              Positioned.fill(
                child: _buildBackground(ref, visualStyle, theme),
              ),
              // 粒子层（仅 vinyl 风格）
              if (visualStyle == PlayerVisualStyle.vinyl)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ParticlesBackground(
                      color: theme.colorScheme.primary,
                      active: isPlaying,
                    ),
                  ),
                ),
              // 主内容
              SafeArea(
                child: Column(
                  children: [
                    _buildAppBar(context, ref),
                    const SizedBox(height: 20),
                    Expanded(
                      flex: 5,
                      child: _buildAlbumArt(
                          ref, visualStyle, isPlaying, theme),
                    ),
                    const SizedBox(height: 20),
                    _buildSongInfo(currentSong, theme),
                    const SizedBox(height: 12),
                    _buildLyricsPreview(theme),
                    const SizedBox(height: 12),
                    _buildSpectrumWithProgress(context, ref, theme),
                    const SizedBox(height: 16),
                    _buildControls(ref, isPlaying, playMode, volume, theme),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 背景层 — 根据风格切换
  Widget _buildBackground(
      WidgetRef ref, PlayerVisualStyle style, ThemeData theme) {
    switch (style) {
      case PlayerVisualStyle.blur:
        // 封面高斯模糊背景
        return Consumer(
          builder: (context, ref, _) {
            final coverData =
                ref.watch(playerProvider.select((s) => s.coverData));
            if (coverData != null) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    Uint8List.fromList(coverData),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              );
            }
            return _defaultGradientBg(theme);
          },
        );

      case PlayerVisualStyle.vinyl:
        // 深色背景
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1a1a2e), Color(0xFF0a0a0a)],
            ),
          ),
        );

      case PlayerVisualStyle.standard:
        return _defaultGradientBg(theme);
    }
  }

  Widget _defaultGradientBg(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.3),
            const Color(0xFF121212),
            const Color(0xFF0A0A0A),
          ],
        ),
      ),
    );
  }

  /// 顶部导航栏
  Widget _buildAppBar(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.keyboard_arrow_down, size: 32),
          ),
          const Spacer(),
          // 睡前定时
          Consumer(
            builder: (context, ref, _) {
              final timer = ref.watch(sleepTimerProvider);
              return IconButton(
                onPressed: () => SleepTimerSheet.show(context),
                icon: Icon(
                  Icons.bedtime_outlined,
                  color: timer.isActive
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white70,
                  size: 20,
                ),
                tooltip: timer.isActive
                    ? '定时 ${timer.remainingFormatted}'
                    : '睡前定时',
              );
            },
          ),
          // 歌词编辑器入口
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LyricsEditorPage(),
                ),
              );
            },
            icon: const Icon(Icons.edit_note, color: Colors.white70, size: 22),
            tooltip: '歌词编辑器',
          ),
          // 保存信息到文件
          Consumer(
            builder: (context, ref, _) {
              final hasCover = ref.watch(
                playerProvider.select((s) => s.coverData != null),
              );
              final hasLrc = ref.watch(
                playerProvider.select((s) => s.lyrics != null),
              );
              final canSave = hasCover || hasLrc;
              return IconButton(
                onPressed: canSave ? () => _saveToFile(context, ref) : null,
                icon: Icon(
                  Icons.save_alt,
                  color: canSave ? Colors.white : Colors.white24,
                  size: 20,
                ),
                tooltip: '保存信息到文件',
              );
            },
          ),
        ],
      ),
    );
  }

  /// 专辑封面 — 根据风格切换，点击切换风格
  Widget _buildAlbumArt(WidgetRef ref, PlayerVisualStyle style,
      bool isPlaying, ThemeData theme) {
    return GestureDetector(
      onTap: () => ref.read(playerVisualStyleProvider.notifier).next(),
      child: Center(
        child: Hero(
          tag: 'album_art',
          child: Consumer(
            builder: (context, ref, _) {
              final coverData = ref.watch(
                playerProvider.select((s) => s.coverData),
              );

              switch (style) {
                case PlayerVisualStyle.vinyl:
                  return VinylDisc(
                    coverData: coverData,
                    isPlaying: isPlaying,
                    size: 280,
                  );

                case PlayerVisualStyle.blur:
                case PlayerVisualStyle.standard:
                  return Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 40,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: coverData != null
                          ? Image.memory(
                              Uint8List.fromList(coverData),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) =>
                                  _buildDefaultCover(theme),
                            )
                          : _buildDefaultCover(theme),
                    ),
                  );
              }
            },
          ),
        ),
      ),
    );
  }

  /// 默认封面
  Widget _buildDefaultCover(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.5),
            theme.colorScheme.tertiary.withValues(alpha: 0.5),
          ],
        ),
      ),
      child: const Icon(Icons.album_rounded, size: 120, color: Colors.white24),
    );
  }

  /// 歌曲信息
  Widget _buildSongInfo(dynamic currentSong, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            currentSong?.title ?? '未知歌曲',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            currentSong?.artist ?? '未知歌手',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white54),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 歌词预览
  Widget _buildLyricsPreview(ThemeData theme) {
    return Consumer(
      builder: (context, ref, _) {
        final lyrics = ref.watch(playerProvider.select((s) => s.lyrics));
        final currentMs = ref.watch(
          playerProvider.select((s) => s.position.inMilliseconds),
        );

        if (lyrics == null || lyrics.lines.isEmpty) {
          return const SizedBox(height: 40);
        }

        int currentLineIndex = -1;
        for (int i = lyrics.lines.length - 1; i >= 0; i--) {
          if (lyrics.lines[i].timeMs.toInt() <= currentMs) {
            currentLineIndex = i;
            break;
          }
        }

        final currentText =
            currentLineIndex >= 0 ? lyrics.lines[currentLineIndex].text : '';
        final nextText = currentLineIndex + 1 < lyrics.lines.length
            ? lyrics.lines[currentLineIndex + 1].text
            : '';

        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const _FullScreenLyricsPage(),
              ),
            );
          },
          onHorizontalDragEnd: (details) {
            // 向左滑动打开全屏歌词
            if (details.primaryVelocity != null &&
                details.primaryVelocity! < -200) {
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const _FullScreenLyricsPage(),
                  transitionsBuilder: (_, animation, __, child) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(1, 0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      )),
                      child: child,
                    );
                  },
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                Text(
                  currentText,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  nextText,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 频谱 + 进度条
  Widget _buildSpectrumWithProgress(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
  ) {
    return Consumer(
      builder: (context, ref, _) {
        final position = ref.watch(playerProvider.select((s) => s.position));
        final duration = ref.watch(playerProvider.select((s) => s.duration));
        final spectrum = ref.watch(playerProvider.select((s) => s.spectrum));
        final abLoopState = ref.watch(playerProvider.select((s) => s.abLoopState));
        final loopStart = ref.watch(playerProvider.select((s) => s.loopStart));
        final loopEnd = ref.watch(playerProvider.select((s) => s.loopEnd));
        final progress = duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
            : 0.0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: 32,
                  width: double.infinity,
                  child: SpectrumView(spectrum: spectrum, opacity: 0.7),
                ),
              ),
              // 进度条 + A-B 区间标记
              SizedBox(
                height: 24,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: [
                        // A-B 循环区间高亮
                        if (abLoopState != ABLoopState.off &&
                            loopStart != null &&
                            duration.inMilliseconds > 0)
                          Positioned(
                            left: (loopStart.inMilliseconds /
                                    duration.inMilliseconds) *
                                constraints.maxWidth,
                            right: loopEnd != null
                                ? (1 -
                                        loopEnd.inMilliseconds /
                                            duration.inMilliseconds) *
                                    constraints.maxWidth
                                : 0,
                            top: 8,
                            bottom: 8,
                            child: Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        // 滑块
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12),
                            activeTrackColor: theme.colorScheme.primary,
                            inactiveTrackColor: Colors.white12,
                            thumbColor: theme.colorScheme.primary,
                          ),
                          child: Slider(
                            value: progress,
                            onChanged: (value) {
                              final newPos = Duration(
                                milliseconds:
                                    (value * duration.inMilliseconds).toInt(),
                              );
                              ref.read(playerProvider.notifier).seekTo(newPos);
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(position),
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    // A-B 复读按钮
                    _buildABLoopButton(ref, abLoopState, loopStart, loopEnd, theme),
                    Text(
                      _formatDuration(duration),
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// A-B 复读循环按钮
  Widget _buildABLoopButton(
    WidgetRef ref,
    ABLoopState abLoopState,
    Duration? loopStart,
    Duration? loopEnd,
    ThemeData theme,
  ) {
    String label;
    Color color;
    switch (abLoopState) {
      case ABLoopState.off:
        label = 'A-B';
        color = Colors.white38;
        break;
      case ABLoopState.setA:
        label = 'A: ${_formatDuration(loopStart ?? Duration.zero)}';
        color = theme.colorScheme.primary.withValues(alpha: 0.8);
        break;
      case ABLoopState.active:
        label = '${_formatDuration(loopStart ?? Duration.zero)} ↔ ${_formatDuration(loopEnd ?? Duration.zero)}';
        color = theme.colorScheme.primary;
        break;
    }

    return GestureDetector(
      onTap: () => ref.read(playerProvider.notifier).toggleABLoop(),
      onLongPress: () => ref.read(playerProvider.notifier).clearABLoop(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: abLoopState == ABLoopState.active
              ? theme.colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
          border: abLoopState != ABLoopState.off
              ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5), width: 1)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: abLoopState != ABLoopState.off
                ? FontWeight.w600
                : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// 播放控制按钮
  Widget _buildControls(
    WidgetRef ref,
    bool isPlaying,
    PlayMode playMode,
    double volume,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            onPressed: () => ref.read(playerProvider.notifier).togglePlayMode(),
            icon: Icon(
              _getPlayModeIcon(playMode),
              color: Colors.white70,
              size: 24,
            ),
          ),
          IconButton(
            onPressed: () => ref.read(playerProvider.notifier).previous(),
            icon: const Icon(Icons.skip_previous_rounded,
                color: Colors.white, size: 36),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary,
            ),
            child: IconButton(
              onPressed: () =>
                  ref.read(playerProvider.notifier).togglePlayPause(),
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
          IconButton(
            onPressed: () => ref.read(playerProvider.notifier).next(),
            icon: const Icon(Icons.skip_next_rounded,
                color: Colors.white, size: 36),
          ),
          // 变速按钮
          Consumer(
            builder: (context, ref, _) {
              final speed = ref.watch(playbackSpeedProvider);
              final isDefault = (speed - 1.0).abs() < 0.01;
              return GestureDetector(
                onTap: () => SpeedControlSheet.show(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isDefault
                        ? Colors.transparent
                        : theme.colorScheme.primary.withValues(alpha: 0.2),
                  ),
                  child: Text(
                    '${speed.toStringAsFixed(speed == speed.roundToDouble() ? 1 : 2)}x',
                    style: TextStyle(
                      color: isDefault ? Colors.white70 : theme.colorScheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  IconData _getPlayModeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.sequential:
        return Icons.repeat;
      case PlayMode.singleLoop:
        return Icons.repeat_one;
      case PlayMode.shuffle:
        return Icons.shuffle;
    }
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> _saveToFile(BuildContext context, WidgetRef ref) async {
    final player = ref.read(playerProvider);
    final song = player.currentSong;
    if (song == null) return;

    try {
      await ref.read(libraryProvider.notifier).saveAllMetadataAndUpdate(
            song: song,
            lyricsText: player.lrcText,
            coverData: player.coverData,
          );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已保存到源文件'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }
}

/// 全屏歌词页面
class _FullScreenLyricsPage extends ConsumerWidget {
  const _FullScreenLyricsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final theme = Theme.of(context);
    final notifier = ref.read(playerProvider.notifier);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () =>
            notifier.togglePlayPause(),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            notifier.next(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            notifier.previous(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.2),
                  const Color(0xFF121212),
                ],
              ),
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  // 频谱背景（低不透明度 + 径向遮罩）
                  if (!Platform.isAndroid)
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
                                  playerProvider.select((s) => s.spectrum));
                              return SpectrumView(
                                spectrum: spec,
                                opacity: 0.25,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white70),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentSong?.title ?? '',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    currentSong?.artist ?? '',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Expanded(child: LyricsView(isFullScreen: true)),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 8, 32, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: () =>
                                  ref.read(playerProvider.notifier).previous(),
                              icon: const Icon(Icons.skip_previous_rounded,
                                  color: Colors.white70, size: 32),
                            ),
                            const SizedBox(width: 24),
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.primary,
                              ),
                              child: IconButton(
                                onPressed: () => ref
                                    .read(playerProvider.notifier)
                                    .togglePlayPause(),
                                icon: Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            IconButton(
                              onPressed: () =>
                                  ref.read(playerProvider.notifier).next(),
                              icon: const Icon(Icons.skip_next_rounded,
                                  color: Colors.white70, size: 32),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
