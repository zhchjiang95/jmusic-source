import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:jmusic/providers/app_providers.dart';

import 'package:jmusic/widgets/mini_player.dart';

/// 主页 - 歌曲库列表
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryState = ref.watch(libraryProvider);
    final playerState = ref.watch(playerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 顶部标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
              child: Row(
                children: [
                  // 应用图标和标题
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.tertiary,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.music_note,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'JMusic',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  // 扫描按钮
                  IconButton(
                    onPressed: libraryState.isScanning
                        ? null
                        : () => _scanDirectory(ref),
                    icon: libraryState.isScanning
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : Icon(
                            Icons.folder_open,
                            color: theme.colorScheme.primary,
                          ),
                    tooltip: '添加音乐目录',
                  ),
                ],
              ),
            ),

            // 歌曲数量统计
            if (libraryState.songs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text(
                      '共 ${libraryState.songs.length} 首歌曲',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 歌曲列表
            Expanded(
              child: libraryState.songs.isEmpty
                  ? _buildEmptyState(context, ref, libraryState)
                  : _buildSongList(context, ref, libraryState, playerState),
            ),

            // 底部迷你播放栏
            if (playerState.currentSong != null) const MiniPlayer(),
          ],
        ),
      ),
    );
  }

  /// 空状态
  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    LibraryState state,
  ) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_music_outlined,
            size: 80,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有歌曲',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角按钮添加音乐目录',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: state.isScanning ? null : () => _scanDirectory(ref),
            icon: const Icon(Icons.folder_open),
            label: const Text('选择音乐目录'),
          ),
        ],
      ),
    );
  }

  /// 歌曲列表
  Widget _buildSongList(
    BuildContext context,
    WidgetRef ref,
    LibraryState libraryState,
    PlayerState playerState,
  ) {
    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: libraryState.songs.length,
      itemBuilder: (context, index) {
        final song = libraryState.songs[index];
        final isCurrentSong =
            playerState.currentSong?.filePath == song.filePath;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isCurrentSong
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : Colors.transparent,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isCurrentSong
                      ? [theme.colorScheme.primary, theme.colorScheme.tertiary]
                      : [const Color(0xFF2A2A3E), const Color(0xFF1E1E2E)],
                ),
              ),
              child: Icon(
                isCurrentSong ? Icons.equalizer : Icons.music_note,
                color: isCurrentSong
                    ? Colors.white
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                size: 22,
              ),
            ),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isCurrentSong
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
                fontWeight: isCurrentSong ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
            trailing: Text(
              _formatDuration(song.duration),
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
            onTap: () {
              // 设置播放列表并播放
              ref.read(playerProvider.notifier).setPlaylist(libraryState.songs);
              ref.read(playerProvider.notifier).playSongAt(index);
            },
          ),
        );
      },
    );
  }

  /// 扫描目录
  Future<void> _scanDirectory(WidgetRef ref) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      await ref.read(libraryProvider.notifier).scanDirectory(result);
      // 更新播放列表
      final songs = ref.read(libraryProvider).songs;
      ref.read(playerProvider.notifier).setPlaylist(songs);
    }
  }

  /// 格式化时长
  String _formatDuration(double seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds.toInt() % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }
}
