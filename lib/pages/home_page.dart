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
              padding: const EdgeInsets.fromLTRB(24, 12, 16, 4),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.tertiary,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.music_note,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'JMusic',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  if (libraryState.songs.isNotEmpty)
                    Text(
                      '${libraryState.songs.length} 首',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: libraryState.isScanning
                        ? null
                        : () => _scanDirectory(ref),
                    icon: libraryState.isScanning
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : Icon(
                            Icons.folder_open,
                            color: theme.colorScheme.primary,
                            size: 22,
                          ),
                    tooltip: '添加音乐目录',
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
            size: 72,
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

  /// 歌曲列表（紧凑表格式布局）
  Widget _buildSongList(
    BuildContext context,
    WidgetRef ref,
    LibraryState libraryState,
    PlayerState playerState,
  ) {
    final theme = Theme.of(context);
    final dimColor = theme.colorScheme.onSurface.withValues(alpha: 0.4);

    return Column(
      children: [
        // 表头
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  '#',
                  style: TextStyle(color: dimColor, fontSize: 12),
                ),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  '标题 / 歌手',
                  style: TextStyle(color: dimColor, fontSize: 12),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '专辑',
                  style: TextStyle(color: dimColor, fontSize: 12),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '大小',
                  style: TextStyle(color: dimColor, fontSize: 12),
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(
                  '格式',
                  style: TextStyle(color: dimColor, fontSize: 12),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '时长',
                  style: TextStyle(color: dimColor, fontSize: 12),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        ),

        // 歌曲行
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: libraryState.songs.length,
            itemExtent: 44, // 固定行高，更紧凑
            itemBuilder: (context, index) {
              final song = libraryState.songs[index];
              final isCurrentSong =
                  playerState.currentSong?.filePath == song.filePath;

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    ref
                        .read(playerProvider.notifier)
                        .setPlaylist(libraryState.songs);
                    ref.read(playerProvider.notifier).playSongAt(index);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: isCurrentSong
                          ? theme.colorScheme.primary.withValues(alpha: 0.12)
                          : null,
                    ),
                    child: Row(
                      children: [
                        // 序号 / 播放指示
                        SizedBox(
                          width: 36,
                          child: isCurrentSong
                              ? Icon(
                                  Icons.equalizer,
                                  color: theme.colorScheme.primary,
                                  size: 16,
                                )
                              : Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: dimColor,
                                    fontSize: 13,
                                  ),
                                ),
                        ),
                        // 标题 + 歌手
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isCurrentSong
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface,
                                  fontWeight: isCurrentSong
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  fontSize: 13,
                                  height: 1.2,
                                ),
                              ),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: dimColor,
                                  fontSize: 11,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 专辑
                        Expanded(
                          flex: 2,
                          child: Text(
                            song.album.isNotEmpty ? song.album : '-',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: dimColor, fontSize: 12),
                          ),
                        ),
                        // 文件大小
                        SizedBox(
                          width: 60,
                          child: Text(
                            _formatFileSize(song.fileSize.toInt()),
                            style: TextStyle(color: dimColor, fontSize: 12),
                          ),
                        ),
                        // 格式
                        SizedBox(
                          width: 50,
                          child: Text(
                            song.format.toUpperCase(),
                            style: TextStyle(color: dimColor, fontSize: 12),
                          ),
                        ),
                        // 时长
                        SizedBox(
                          width: 48,
                          child: Text(
                            _formatDuration(song.duration),
                            style: TextStyle(color: dimColor, fontSize: 12),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 扫描目录
  Future<void> _scanDirectory(WidgetRef ref) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      await ref.read(libraryProvider.notifier).scanDirectory(result);
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

  /// 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
