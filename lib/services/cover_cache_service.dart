import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:jmusic/src/rust/api/scanner.dart' as rust_scanner;

/// 专辑封面缓存服务（管理音频文件中提取的封面缩略图）
class CoverCacheService {
  CoverCacheService._();
  static final CoverCacheService instance = CoverCacheService._();

  Directory? _cacheDir;
  bool _isInitialized = false;

  /// 初始化缓存目录
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final tempDir = await getTemporaryDirectory();
      _cacheDir = Directory('${tempDir.path}/jmusic_covers');
      if (!_cacheDir!.existsSync()) {
        await _cacheDir!.create(recursive: true);
      }
      _isInitialized = true;
    } catch (e) {
      print('初始化封面缓存目录失败: $e');
    }
  }


  /// 获取专辑和歌手的唯一 Hex 编码作为文件名
  String _getCacheKey(String album, String artist) {
    final key = '${album.trim()}_${artist.trim()}';
    final bytes = utf8.encode(key);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 获取专辑封面的缓存文件路径，如果不存在则异步提取并写入
  /// 
  /// [filePath] 本地歌曲文件路径（用于提取封面）
  /// [album] 专辑名称
  /// [artist] 歌手名称
  Future<String?> getCoverPath({
    required String filePath,
    required String album,
    required String artist,
  }) async {
    await init();
    if (_cacheDir == null) return null;

    final key = _getCacheKey(album, artist);
    final cacheFile = File('${_cacheDir!.path}/$key.jpg');

    // 1. 如果缓存已存在，直接返回
    if (await cacheFile.exists()) {
      return cacheFile.path;
    }

    // 2. 如果是 WebDAV 云端文件且尚未缓存到本地，我们无法直接读取 lofty 标签封面，返回 null
    if (filePath.startsWith('webdav://')) {
      return null;
    }

    // 3. 异步调用 Rust 侧的 lofty 提取封面
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final coverData = await rust_scanner.readEmbeddedCover(filePath: filePath);
      if (coverData != null && coverData.isNotEmpty) {
        // 后台写入缓存文件
        await cacheFile.writeAsBytes(coverData);
        return cacheFile.path;
      }
    } catch (e) {
      print('从文件提取封面失败 [$filePath]: $e');
    }

    return null;
  }

  /// 手动保存下载好的网络封面到本地缓存
  Future<String?> saveCoverBytes({
    required String album,
    required String artist,
    required List<int> bytes,
  }) async {
    await init();
    if (_cacheDir == null) return null;

    final key = _getCacheKey(album, artist);
    final cacheFile = File('${_cacheDir!.path}/$key.jpg');

    try {
      await cacheFile.writeAsBytes(bytes);
      return cacheFile.path;
    } catch (e) {
      print('保存网络封面到缓存失败: $e');
      return null;
    }
  }
}
