import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/widgets/lyrics_view.dart';

/// 全屏播放页面
class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只监听基本歌曲信息和播放状态（不含 position/coverData）
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final playMode = ref.watch(playerProvider.select((s) => s.playMode));
    final volume = ref.watch(playerProvider.select((s) => s.volume));
    final hasLyrics = ref.watch(playerProvider.select((s) => s.lyrics != null));
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
                  theme.colorScheme.primary.withValues(alpha: 0.3),
                  const Color(0xFF121212),
                  const Color(0xFF0A0A0A),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // 顶部导航栏
                  _buildAppBar(context, ref, hasLyrics),
                  const SizedBox(height: 20),

                  // 专辑封面（独立 Consumer）
                  Expanded(flex: 5, child: _buildAlbumArt(theme)),

                  const SizedBox(height: 20),

                  // 歌曲信息
                  _buildSongInfo(currentSong, theme),
                  const SizedBox(height: 12),

                  // 歌词预览（两行）
                  _buildLyricsPreview(theme),
                  const SizedBox(height: 12),

                  // 进度条（独立 Consumer）
                  _buildProgressBar(context, ref, theme),
                  const SizedBox(height: 16),

                  // 播放控制按钮
                  _buildControls(ref, isPlaying, playMode, volume, theme),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 顶部导航栏
  Widget _buildAppBar(BuildContext context, WidgetRef ref, bool hasLyrics) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.keyboard_arrow_down, size: 32),
          ),
          const Spacer(),
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
                ),
                tooltip: '保存信息到文件',
              );
            },
          ),
          IconButton(
            onPressed: hasLyrics
                ? () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const _FullScreenLyricsPage(),
                      ),
                    );
                  }
                : null,
            icon: Icon(
              Icons.lyrics_outlined,
              color: hasLyrics ? Colors.white : Colors.white24,
            ),
          ),
        ],
      ),
    );
  }

  /// 专辑封面（使用独立 Consumer 避免因 position 更新而重建）
  Widget _buildAlbumArt(ThemeData theme) {
    return Center(
      child: Hero(
        tag: 'album_art',
        child: Consumer(
          builder: (context, ref, _) {
            final coverData = ref.watch(
              playerProvider.select((s) => s.coverData),
            );
            return Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
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
                        errorBuilder: (_, __, ___) => _buildDefaultCover(theme),
                      )
                    : _buildDefaultCover(theme),
              ),
            );
          },
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

  /// 歌词预览（当前行 + 下一行，独立 Consumer）
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

        // 找到当前歌词行
        int currentLineIndex = -1;
        for (int i = lyrics.lines.length - 1; i >= 0; i--) {
          if (lyrics.lines[i].timeMs.toInt() <= currentMs) {
            currentLineIndex = i;
            break;
          }
        }

        final currentText = currentLineIndex >= 0
            ? lyrics.lines[currentLineIndex].text
            : '';
        final nextText = currentLineIndex + 1 < lyrics.lines.length
            ? lyrics.lines[currentLineIndex + 1].text
            : '';

        return Padding(
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
        );
      },
    );
  }

  /// 进度条（独立 Consumer，只监听 position 和 duration）
  Widget _buildProgressBar(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
  ) {
    return Consumer(
      builder: (context, ref, _) {
        final position = ref.watch(playerProvider.select((s) => s.position));
        final duration = ref.watch(playerProvider.select((s) => s.duration));
        final progress = duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : 0.0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                  activeTrackColor: theme.colorScheme.primary,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: theme.colorScheme.primary,
                ),
                child: Slider(
                  value: progress,
                  onChanged: (value) {
                    final newPos = Duration(
                      milliseconds: (value * duration.inMilliseconds).toInt(),
                    );
                    ref.read(playerProvider.notifier).seekTo(newPos);
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
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _formatDuration(duration),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
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
          // 播放模式
          IconButton(
            onPressed: () => ref.read(playerProvider.notifier).togglePlayMode(),
            icon: Icon(
              _getPlayModeIcon(playMode),
              color: Colors.white70,
              size: 24,
            ),
          ),
          // 上一首
          IconButton(
            onPressed: () => ref.read(playerProvider.notifier).previous(),
            icon: const Icon(
              Icons.skip_previous_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
          // 播放/暂停
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
          // 下一首
          IconButton(
            onPressed: () => ref.read(playerProvider.notifier).next(),
            icon: const Icon(
              Icons.skip_next_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
          // 音量
          IconButton(
            onPressed: () {
              final vol = volume > 0 ? 0.0 : 0.8;
              ref.read(playerProvider.notifier).setVolume(vol);
            },
            icon: Icon(
              volume > 0 ? Icons.volume_up : Icons.volume_off,
              color: Colors.white70,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  /// 获取播放模式图标
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

  /// 格式化时长
  String _formatDuration(Duration d) {
    final mins = d.inMinutes.toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  /// 将歌曲信息、歌词和封面保存到源文件
  Future<void> _saveToFile(BuildContext context, WidgetRef ref) async {
    final player = ref.read(playerProvider);
    final song = player.currentSong;
    if (song == null) return;

    try {
      await ref
          .read(libraryProvider.notifier)
          .saveAllMetadataAndUpdate(
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
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
              child: Column(
                children: [
                  // 顶部栏
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white70,
                          ),
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
                  // 歌词滚动区域
                  const Expanded(child: LyricsView(isFullScreen: true)),
                  // 底部简化控制栏
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 8, 32, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () =>
                              ref.read(playerProvider.notifier).previous(),
                          icon: const Icon(
                            Icons.skip_previous_rounded,
                            color: Colors.white70,
                            size: 32,
                          ),
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
                          icon: const Icon(
                            Icons.skip_next_rounded,
                            color: Colors.white70,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
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
