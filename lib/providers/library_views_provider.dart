import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/providers/webdav_provider.dart';
import 'package:jmusic/src/rust/models/song.dart';

/// 专辑数据模型
class AlbumModel {
  /// 专辑名称
  final String name;

  /// 歌手（或主要歌手）
  final String artist;

  /// 包含的歌曲
  final List<Song> songs;

  AlbumModel({
    required this.name,
    required this.artist,
    required this.songs,
  });

  /// 专辑的代表歌曲（用来获取封面）
  Song get representativeSong => songs.first;

  /// 时长总和（秒）
  double get totalDuration => songs.fold(0, (sum, s) => sum + s.duration);
}

/// 艺术家数据模型
class ArtistModel {
  /// 艺术家名称
  final String name;

  /// 包含的所有歌曲
  final List<Song> songs;

  /// 包含的所有专辑
  final List<AlbumModel> albums;

  ArtistModel({
    required this.name,
    required this.songs,
    required this.albums,
  });
}

/// 全局歌曲合并 Provider（合并本地歌曲库与 WebDAV 歌曲）
final allSongsProvider = Provider<List<Song>>((ref) {
  final libraryState = ref.watch(libraryProvider);
  final webDavState = ref.watch(webDavProvider);
  return [...libraryState.songs, ...webDavState.songs];
});

/// 全局专辑聚类 Provider
final allAlbumsProvider = Provider<List<AlbumModel>>((ref) {
  final songs = ref.watch(allSongsProvider);
  final Map<String, List<Song>> groups = {};

  for (final song in songs) {
    // 专辑以 "专辑名__歌手名" 作为 key，防止同名不同歌手的专辑被合并
    final key = '${song.album.trim()}__${song.artist.trim()}';
    groups.putIfAbsent(key, () => []).add(song);
  }

  final albums = groups.entries.map((entry) {
    final parts = entry.key.split('__');
    return AlbumModel(
      name: parts[0].isEmpty ? '未知专辑' : parts[0],
      artist: parts[1].isEmpty ? '未知歌手' : parts[1],
      songs: entry.value,
    );
  }).toList();

  // 按专辑名称排序
  albums.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return albums;
});

/// 全局艺术家聚类 Provider
final allArtistsProvider = Provider<List<ArtistModel>>((ref) {
  final songs = ref.watch(allSongsProvider);
  final albums = ref.watch(allAlbumsProvider);

  // 1. 按歌手名字归类歌曲
  final Map<String, List<Song>> artistSongs = {};
  for (final song in songs) {
    final artist = song.artist.trim().isEmpty ? '未知歌手' : song.artist.trim();
    // 应对合唱（/ 或 , 分割）的简单做法是直接按整个 artist 字符串做为 key。
    // 如果后续需要多歌手展示，可以在这里 split 并做多键匹配。
    artistSongs.putIfAbsent(artist, () => []).add(song);
  }

  // 2. 按歌手名字归类专辑
  final Map<String, List<AlbumModel>> artistAlbums = {};
  for (final album in albums) {
    final artist = album.artist.isEmpty ? '未知歌手' : album.artist;
    artistAlbums.putIfAbsent(artist, () => []).add(album);
  }

  // 3. 构建 ArtistModel 列表
  final artists = artistSongs.entries.map((entry) {
    final artistName = entry.key;
    return ArtistModel(
      name: artistName,
      songs: entry.value,
      albums: artistAlbums[artistName] ?? [],
    );
  }).toList();

  // 按歌手名字排序
  artists.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return artists;
});
