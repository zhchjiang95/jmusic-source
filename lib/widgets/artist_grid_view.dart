import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/providers/library_views_provider.dart';
import 'package:jmusic/services/cover_cache_service.dart';
import 'package:jmusic/src/rust/models/song.dart';


/// 预设的现代化、柔和渐变色盘
const List<List<Color>> _presetGradients = [
  [Color(0xFF8EC5FC), Color(0xFFE0C3FC)], // 冰粉蓝
  [Color(0xFFFA709A), Color(0xFFFEE140)], // 蜜桃黄
  [Color(0xFF4FACFE), Color(0xFF00F2FE)], // 碧空蓝
  [Color(0xFF43E97B), Color(0xFF38F9D7)], // 薄荷绿
  [Color(0xFFF6D365), Color(0xFFFDA085)], // 暖阳橙
  [Color(0xFFA18CD1), Color(0xFFFBC2EB)], // 丁香紫
  [Color(0xFFFF9A9E), Color(0xFFFECFEF)], // 樱花粉
  [Color(0xFF11998E), Color(0xFF38EF7D)], // 翡翠绿
  [Color(0xFF2193B0), Color(0xFF6DD5ED)], // 极光青
  [Color(0xFFEE0979), Color(0xFFFF6A00)], // 热情橙红
];

/// 字符串哈希方法（生成稳定数字）
int _hashString(String str) {
  int hash = 0;
  for (int i = 0; i < str.length; i++) {
    hash = str.codeUnitAt(i) + ((hash << 5) - hash);
  }
  return hash;
}

/// 艺术家网格视图
class ArtistGridView extends ConsumerWidget {
  final String searchQuery;

  const ArtistGridView({
    super.key,
    required this.searchQuery,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(allArtistsProvider);
    final theme = Theme.of(context);

    // 过滤歌手列表
    final filteredArtists = artists.where((artist) {
      if (searchQuery.isEmpty) return true;
      return artist.name.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    if (filteredArtists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_alt_outlined,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 12),
            Text(
              '没有找到相关歌手',
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
        maxCrossAxisExtent: 150,
        mainAxisSpacing: 20,
        crossAxisSpacing: 16,
        childAspectRatio: 0.70,
      ),
      itemCount: filteredArtists.length,
      itemBuilder: (context, index) {
        final artist = filteredArtists[index];
        return _ArtistCard(artist: artist);
      },
    );
  }
}

/// 艺术家卡片组件
class _ArtistCard extends StatelessWidget {
  final ArtistModel artist;

  const _ArtistCard({required this.artist});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => _showArtistDetails(context),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 圆形歌手头像（使用 Collage + 渐变兜底）
          AspectRatio(
            aspectRatio: 1.0,
            child: _ArtistAvatar(artist: artist, size: 120),
          ),
          const SizedBox(height: 6),
          // 歌手名
          Text(
            artist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          // 专辑数与歌曲数
          Text(
            '${artist.albums.length} 专辑 • ${artist.songs.length} 单曲',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  void _showArtistDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ArtistDetailSheet(artist: artist),
    );
  }
}

/// 高级歌手头像组件（支持 4 图拼贴或哈希渐变文字兜底）
class _ArtistAvatar extends StatelessWidget {
  final ArtistModel artist;
  final double size;

  const _ArtistAvatar({
    required this.artist,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 收集有封面的专辑/曲目列表作为拼贴图源 (最多 4 个)
    final List<Song> representativeSongs = [];
    final Set<String> keySet = {};
    for (final song in artist.songs) {
      final key = '${song.album}_${song.artist}';
      if (!keySet.contains(key)) {
        keySet.add(key);
        representativeSongs.add(song);
        if (representativeSongs.length >= 4) break;
      }
    }

    return FutureBuilder<List<String?>>(
      future: Future.wait(
        representativeSongs.map(
          (song) => CoverCacheService.instance.getCoverPath(
            filePath: song.filePath,
            album: song.album,
            artist: song.artist,
          ),
        ),
      ),
      builder: (context, snapshot) {
        final List<String> validCovers = [];
        if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
          for (final path in snapshot.data!) {
            if (path != null && path.isNotEmpty) {
              validCovers.add(path);
            }
          }
        }

        // 1. 如果有 4 个及以上的封面，展示 2x2 拼图
        if (validCovers.length >= 4) {
          return ClipOval(
            child: SizedBox(
              width: size,
              height: size,
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: Image.file(File(validCovers[0]), fit: BoxFit.cover, cacheWidth: 100, cacheHeight: 100)),
                        Expanded(child: Image.file(File(validCovers[1]), fit: BoxFit.cover, cacheWidth: 100, cacheHeight: 100)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: Image.file(File(validCovers[2]), fit: BoxFit.cover, cacheWidth: 100, cacheHeight: 100)),
                        Expanded(child: Image.file(File(validCovers[3]), fit: BoxFit.cover, cacheWidth: 100, cacheHeight: 100)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // 2. 如果只有 1-3 张封面，直接显示第一张作为头像
        if (validCovers.isNotEmpty) {
          return ClipOval(
            child: Image.file(
              File(validCovers.first),
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: 180,
              cacheHeight: 180,
              errorBuilder: (_, __, ___) => _buildTextAvatar(theme),
            ),
          );
        }

        // 3. 兜底：生成式哈希渐变文字头像
        return _buildTextAvatar(theme);
      },
    );
  }

  Widget _buildTextAvatar(ThemeData theme) {
    final hash = _hashString(artist.name);
    final gradient = _presetGradients[hash.abs() % _presetGradients.length];
    final initialLetter = artist.name.isNotEmpty ? artist.name[0].toUpperCase() : "?";

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initialLetter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.35,
          fontWeight: FontWeight.bold,
          shadows: const [
            Shadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            )
          ],
        ),
      ),
    );
  }
}

/// 艺术家歌曲/专辑详情半页弹窗
class _ArtistDetailSheet extends ConsumerWidget {
  final ArtistModel artist;

  const _ArtistDetailSheet({required this.artist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final playerState = ref.watch(playerProvider);

    return Container(
      height: size.height * 0.85,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A), // 经典黑金质感背景
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          // 顶部滑条
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 艺术家头部
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                _ArtistAvatar(artist: artist, size: 80),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '本地包含 ${artist.albums.length} 张专辑 • ${artist.songs.length} 首曲目',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),

          // 播放按钮栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      final notifier = ref.read(playerProvider.notifier);
                      notifier.setPlaylist(artist.songs);
                      notifier.playSongAt(0);
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('播放全部歌曲'),
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
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final notifier = ref.read(playerProvider.notifier);
                      if (playerState.playMode != PlayMode.shuffle) {
                        notifier.togglePlayMode();
                      }
                      notifier.setPlaylist(artist.songs);
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

          // 下方区域分：专辑横滑 + 所有曲目列表
          Expanded(
            child: CustomScrollView(
              slivers: [
                // 专辑模块标题
                if (artist.albums.isNotEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text(
                        '专辑',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                // 专辑列表横滑
                if (artist.albums.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: artist.albums.length,
                        itemBuilder: (context, idx) {
                          final album = artist.albums[idx];
                          return _SmallAlbumCard(album: album);
                        },
                      ),
                    ),
                  ),

                // 歌曲模块标题
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Text(
                      '所有曲目',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                // 所有曲目列表
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, idx) {
                      final song = artist.songs[idx];
                      final isCurrent = playerState.currentSong?.filePath == song.filePath;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
                        leading: SizedBox(
                          width: 24,
                          child: Center(
                            child: isCurrent && playerState.isPlaying
                                ? Icon(Icons.volume_up_rounded, color: theme.colorScheme.primary, size: 16)
                                : Text(
                                    '${idx + 1}',
                                    style: TextStyle(
                                      color: isCurrent ? theme.colorScheme.primary : Colors.white54,
                                      fontSize: 12,
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
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          song.album,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white30, fontSize: 10),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatSongDuration(song.duration),
                              style: const TextStyle(color: Colors.white24, fontSize: 10),
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 16),
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
                                  child: Text('下一首播放', style: TextStyle(color: Colors.white, fontSize: 12)),
                                ),
                                const PopupMenuItem(
                                  value: 'add_queue',
                                  child: Text('添加到播放队列', style: TextStyle(color: Colors.white, fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        onTap: () {
                          final notifier = ref.read(playerProvider.notifier);
                          notifier.setPlaylist(artist.songs);
                          notifier.playSongAt(idx);
                        },
                      );
                    },
                    childCount: artist.songs.length,
                  ),
                ),
                
                // 底部占位
                const SliverToBoxAdapter(
                  child: SizedBox(height: 32),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  String _formatSongDuration(double durationSecs) {
    final duration = Duration(seconds: durationSecs.toInt());
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 歌手详情内显示的横滑小专辑卡片
class _SmallAlbumCard extends StatelessWidget {
  final AlbumModel album;

  const _SmallAlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () {
        // 关闭当前歌手详情弹窗，并在外层弹出专辑详情。
        // 为了方便，直接再次显示该专辑的详情 sheet。
        Navigator.pop(context);
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => Consumer(
            builder: (_, ref, __) {
              // 我们直接调用之前写在 album_grid_view.dart 中的 _AlbumDetailSheet
              // 这里的 _AlbumDetailSheet 由于在 album_grid_view.dart 是私有的，
              // 我们其实可以在这里拷贝一份或重新引用。为了模块独立且干净，我们直接在这里也实现它，
              // 或者跳转前让用户看到，我们在这里使用 _showSmallAlbumDetails。
              // 我们可以在下面直接复现一个简化版的 AlbumDetailSheet。
              // 由于是同一个 UI 样式，我们直接在下方声明私有详情卡片。
              return _SmallAlbumDetailSheet(album: album);
            },
          ),
        );
      },
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 专辑封面
            AspectRatio(
              aspectRatio: 1.0,
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
                    borderRadius: BorderRadius.circular(8),
                    child: hasCover
                        ? Image.file(
                            File(snapshot.data!),
                            fit: BoxFit.cover,
                            cacheWidth: 120,
                            cacheHeight: 120,
                            errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
                          )
                        : _buildPlaceholder(theme),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
            ),
            Text(
              '${album.songs.length} 首',
              style: const TextStyle(color: Colors.white38, fontSize: 9),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: Colors.white.withValues(alpha: 0.05),
      child: const Center(
        child: Icon(Icons.album_rounded, size: 24, color: Colors.white24),
      ),
    );
  }
}

/// 复制一份简版 _SmallAlbumDetailSheet，保证可以在歌手页面内无缝打开对应专辑
class _SmallAlbumDetailSheet extends ConsumerWidget {
  final AlbumModel album;

  const _SmallAlbumDetailSheet({required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final playerState = ref.watch(playerProvider);

    return Container(
      height: size.height * 0.8,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))
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
                                fit: BoxFit.cover,
                                cacheWidth: 150,
                                cacheHeight: 150,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  child: const Icon(Icons.album, color: Colors.white24, size: 36),
                                ),
                              )
                            : Container(
                                color: Colors.white.withValues(alpha: 0.05),
                                child: const Icon(Icons.album, color: Colors.white24, size: 36),
                              ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        album.artist,
                        style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w500, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${album.songs.length} 首歌曲',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      final notifier = ref.read(playerProvider.notifier);
                      notifier.setPlaylist(album.songs);
                      notifier.playSongAt(0);
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('播放全部'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 24),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: album.songs.length,
              itemBuilder: (context, index) {
                final song = album.songs[index];
                final isCurrent = playerState.currentSong?.filePath == song.filePath;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
                  leading: SizedBox(
                    width: 24,
                    child: Center(
                      child: isCurrent && playerState.isPlaying
                          ? Icon(Icons.volume_up_rounded, color: theme.colorScheme.primary, size: 14)
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: isCurrent ? theme.colorScheme.primary : Colors.white54,
                                fontSize: 12,
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
                      fontSize: 13,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatSongDuration(song.duration),
                        style: const TextStyle(color: Colors.white24, fontSize: 10),
                      ),
                    ],
                  ),
                  onTap: () {
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

  String _formatSongDuration(double durationSecs) {
    final duration = Duration(seconds: durationSecs.toInt());
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
