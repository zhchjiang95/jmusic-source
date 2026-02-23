import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/widgets/lyrics_view.dart';

/// 全屏播放页面
class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerProvider);
    final theme = Theme.of(context);

    return Scaffold(
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
              _buildAppBar(context, state),
              const SizedBox(height: 20),

              // 专辑封面
              Expanded(flex: 5, child: _buildAlbumArt(context, state, theme)),

              const SizedBox(height: 20),

              // 歌曲信息
              _buildSongInfo(context, state, theme),
              const SizedBox(height: 24),

              // 进度条
              _buildProgressBar(context, ref, state, theme),
              const SizedBox(height: 16),

              // 播放控制按钮
              _buildControls(context, ref, state, theme),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部导航栏
  Widget _buildAppBar(BuildContext context, PlayerState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.keyboard_arrow_down, size: 32),
          ),
          const Spacer(),
          Text(
            '正在播放',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              // 显示歌词弹窗
              if (state.lyrics != null) {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: const Color(0xFF1E1E2E),
                  isScrollControlled: true,
                  builder: (_) => SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: const LyricsView(),
                  ),
                );
              }
            },
            icon: const Icon(Icons.lyrics_outlined),
          ),
        ],
      ),
    );
  }

  /// 专辑封面
  Widget _buildAlbumArt(
    BuildContext context,
    PlayerState state,
    ThemeData theme,
  ) {
    return Center(
      child: Hero(
        tag: 'album_art',
        child: Container(
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
            child: state.coverData != null
                ? Image.memory(
                    Uint8List.fromList(state.coverData!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildDefaultCover(theme),
                  )
                : _buildDefaultCover(theme),
          ),
        ),
      ),
    );
  }

  /// 默认封面（无在线封面时显示）
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
  Widget _buildSongInfo(
    BuildContext context,
    PlayerState state,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            state.currentSong?.title ?? '未知歌曲',
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
            state.currentSong?.artist ?? '未知歌手',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white54),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 进度条
  Widget _buildProgressBar(
    BuildContext context,
    WidgetRef ref,
    PlayerState state,
    ThemeData theme,
  ) {
    final position = state.position;
    final duration = state.duration;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
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
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                Text(
                  _formatDuration(duration),
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 播放控制按钮
  Widget _buildControls(
    BuildContext context,
    WidgetRef ref,
    PlayerState state,
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
              _getPlayModeIcon(state.playMode),
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
                state.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
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
              // 简易音量切换
              final vol = state.volume > 0 ? 0.0 : 0.8;
              ref.read(playerProvider.notifier).setVolume(vol);
            },
            icon: Icon(
              state.volume > 0 ? Icons.volume_up : Icons.volume_off,
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
}
