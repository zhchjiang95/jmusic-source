import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/providers/library_views_provider.dart';
import 'package:jmusic/services/cover_cache_service.dart';


/// 专辑网格视图
class AlbumGridView extends ConsumerWidget {
  final String searchQuery;

  const AlbumGridView({
    super.key,
    required this.searchQuery,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(allAlbumsProvider);
    final theme = Theme.of(context);

    // 过滤专辑列表
    final filteredAlbums = albums.where((album) {
      if (searchQuery.isEmpty) return true;
      final q = searchQuery.toLowerCase();
      return album.name.toLowerCase().contains(q) ||
          album.artist.toLowerCase().contains(q);
    }).toList();

    if (filteredAlbums.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.album_outlined,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 12),
            Text(
              '没有找到相关专辑',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.78,
      ),
      itemCount: filteredAlbums.length,
      itemBuilder: (context, index) {
        final album = filteredAlbums[index];
        return _AlbumCard(album: album);
      },
    );
  }
}

/// 专辑卡片组件
class _AlbumCard extends StatelessWidget {
  final AlbumModel album;

  const _AlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => _showAlbumDetails(context),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 专辑封面
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: FutureBuilder<String?>(
                future: CoverCacheService.instance.getCoverPath(
                  filePath: album.representativeSong.filePath,
                  album: album.name,
                  artist: album.artist,
                ),
                builder: (context, snapshot) {
                  final hasCover = snapshot.connectionState == ConnectionState.done &&
                      snapshot.data != null;

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: hasCover
                        ? Image.file(
                            File(snapshot.data!),
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            cacheWidth: 250, // 限制最大缓存像素以省内内存
                            cacheHeight: 250,
                            errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
                          )
                        : _buildPlaceholder(theme),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 专辑名称
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          // 歌手名称
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            child: Text(
              album.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
      child: Center(
        child: Icon(
          Icons.album_rounded,
          size: 48,
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  /// 弹出专辑歌曲列表详情半屏弹窗
  void _showAlbumDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AlbumDetailSheet(album: album),
    );
  }
}

/// 专辑详情半页弹窗
class _AlbumDetailSheet extends ConsumerWidget {
  final AlbumModel album;

  const _AlbumDetailSheet({required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final playerState = ref.watch(playerProvider);

    return Container(
      height: size.height * 0.8,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E), // 现代极简暗色背景
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          // 顶部小横条
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // 专辑头部信息
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 专辑封面
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      )
                    ],
                  ),
                  child: FutureBuilder<String?>(
                    future: CoverCacheService.instance.getCoverPath(
                      filePath: album.representativeSong.filePath,
                      album: album.name,
                      artist: album.artist,
                    ),
                    builder: (context, snapshot) {
                      final hasCover = snapshot.connectionState == ConnectionState.done &&
                          snapshot.data != null;

                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: hasCover
                            ? Image.file(
                                File(snapshot.data!),
                                fit: BoxFit.cover,
                                cacheWidth: 200,
                                cacheHeight: 200,
                                errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
                              )
                            : _buildPlaceholder(theme),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // 专辑名 & 歌手 & 时长
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 18,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        album.artist,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${album.songs.length} 首歌曲 • 时长 ${formatTotalDuration(album.totalDuration)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 动作按钮栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                // 播放全部
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      final notifier = ref.read(playerProvider.notifier);
                      notifier.setPlaylist(album.songs);
                      notifier.playSongAt(0);
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('播放全部'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 打乱播放
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final notifier = ref.read(playerProvider.notifier);
                      // 设置为随机播放模式
                      if (playerState.playMode != PlayMode.shuffle) {
                        notifier.togglePlayMode();
                      }
                      notifier.setPlaylist(album.songs);
                      notifier.playSongAt(0);
                    },
                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                    label: const Text('打乱播放'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 24),

          // 歌曲列表区域
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: album.songs.length,
              itemBuilder: (context, index) {
                final song = album.songs[index];
                final isCurrent = playerState.currentSong?.filePath == song.filePath;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                  leading: SizedBox(
                    width: 32,
                    child: Center(
                      child: isCurrent && playerState.isPlaying
                          ? _buildPlayingIndicator(theme)
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: isCurrent ? theme.colorScheme.primary : Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                    ),
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? theme.colorScheme.primary : Colors.white,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatSongDuration(song.duration),
                        style: const TextStyle(color: Colors.white30, fontSize: 11),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 18),
                        color: const Color(0xFF2A2A2A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        onSelected: (value) {
                          final notifier = ref.read(playerProvider.notifier);
                          if (value == 'play_next') {
                            notifier.playNextInQueue(song);
                          } else if (value == 'add_queue') {
                            notifier.addToQueue(song);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'play_next',
                            child: Text('下一首播放', style: TextStyle(color: Colors.white, fontSize: 13)),
                          ),
                          const PopupMenuItem(
                            value: 'add_queue',
                            child: Text('添加到播放队列', style: TextStyle(color: Colors.white, fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  onTap: () {
                    // 双击或单击都可以直接播放，并且设置当前专辑为播放列表
                    final notifier = ref.read(playerProvider.notifier);
                    notifier.setPlaylist(album.songs);
                    notifier.playSongAt(index);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
      child: Center(
        child: Icon(
          Icons.album_rounded,
          size: 36,
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _buildPlayingIndicator(ThemeData theme) {
    return Icon(
      Icons.volume_up_rounded,
      color: theme.colorScheme.primary,
      size: 16,
    );
  }

  /// 格式化时长总和 (小时:分钟)
  String formatTotalDuration(double durationSecs) {
    final duration = Duration(seconds: durationSecs.toInt());
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '$hours 小时 $minutes 分钟';
    }
    return '$minutes 分钟';
  }

  /// 格式化单首歌曲时长 (分:秒)
  String formatSongDuration(double durationSecs) {
    final duration = Duration(seconds: durationSecs.toInt());
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
