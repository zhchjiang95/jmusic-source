import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/services/webdav_service.dart';
import 'package:jmusic/src/rust/models/song.dart';

/// WebDAV 音乐源状态
class WebDavState {
  final List<WebDavConfig> configs;
  final bool isScanning;
  final String? error;
  final List<Song> songs; // WebDAV 扫描到的歌曲
  final double? downloadProgress; // 当前下载进度

  const WebDavState({
    this.configs = const [],
    this.isScanning = false,
    this.error,
    this.songs = const [],
    this.downloadProgress,
  });

  WebDavState copyWith({
    List<WebDavConfig>? configs,
    bool? isScanning,
    String? error,
    List<Song>? songs,
    double? downloadProgress,
    bool clearError = false,
    bool clearProgress = false,
  }) {
    return WebDavState(
      configs: configs ?? this.configs,
      isScanning: isScanning ?? this.isScanning,
      error: clearError ? null : (error ?? this.error),
      songs: songs ?? this.songs,
      downloadProgress:
          clearProgress ? null : (downloadProgress ?? this.downloadProgress),
    );
  }
}

/// WebDAV Provider
final webDavProvider =
    NotifierProvider<WebDavNotifier, WebDavState>(WebDavNotifier.new);

class WebDavNotifier extends Notifier<WebDavState> {
  final WebDavService _service = WebDavService();

  @override
  WebDavState build() {
    _loadConfigs();
    return const WebDavState();
  }

  Future<void> _loadConfigs() async {
    final configs = await WebDavService.loadConfigs();
    state = state.copyWith(configs: configs);
    // 自动扫描已有配置
    if (configs.isNotEmpty) {
      scanAll();
    }
  }

  /// 添加 WebDAV 配置
  Future<bool> addConfig(WebDavConfig config) async {
    // 测试连接
    final ok = await _service.testConnection(config);
    if (!ok) {
      state = state.copyWith(error: '连接失败，请检查地址和账号');
      return false;
    }

    final configs = [...state.configs, config];
    await WebDavService.saveConfigs(configs);
    state = state.copyWith(configs: configs, clearError: true);

    // 扫描新添加的源
    await _scanConfig(config);
    return true;
  }

  /// 删除 WebDAV 配置
  Future<void> removeConfig(int index) async {
    if (index < 0 || index >= state.configs.length) return;
    final configs = [...state.configs]..removeAt(index);
    await WebDavService.saveConfigs(configs);

    // 移除该源的歌曲
    final removedConfig = state.configs[index];
    final songs = state.songs
        .where((s) => !s.filePath.startsWith('webdav://${removedConfig.url}'))
        .toList();

    state = state.copyWith(configs: configs, songs: songs);
  }

  /// 扫描所有 WebDAV 源
  Future<void> scanAll() async {
    state = state.copyWith(isScanning: true, clearError: true);
    final allSongs = <Song>[];

    for (final config in state.configs) {
      final songs = await _scanConfigSongs(config);
      allSongs.addAll(songs);
    }

    state = state.copyWith(isScanning: false, songs: allSongs);
  }

  /// 扫描单个配置
  Future<void> _scanConfig(WebDavConfig config) async {
    state = state.copyWith(isScanning: true);
    final newSongs = await _scanConfigSongs(config);
    final songs = [...state.songs, ...newSongs];
    state = state.copyWith(isScanning: false, songs: songs);
  }

  /// 扫描配置并返回 Song 列表
  Future<List<Song>> _scanConfigSongs(WebDavConfig config) async {
    try {
      final files = await _service.listAllAudioFiles(config, '/');
      return files.map((f) {
        final ext = f.name.split('.').last.toLowerCase();
        final title = f.name.contains('.')
            ? f.name.substring(0, f.name.lastIndexOf('.'))
            : f.name;

        // 尝试从文件名解析 "歌手 - 标题" 格式
        String songTitle = title;
        String artist = '未知歌手';
        if (title.contains(' - ')) {
          final parts = title.split(' - ');
          artist = parts[0].trim();
          songTitle = parts.sublist(1).join(' - ').trim();
        }

        return Song(
          // 用 webdav:// 前缀标识远程文件
          filePath: 'webdav://${config.url}|${f.href}',
          title: songTitle,
          artist: artist,
          album: config.name,
          duration: 0, // 未知，播放时获取
          fileSize: BigInt.from(f.contentLength),
          format: ext,
          songmid: null,
          albummid: null,
          modifiedAt: BigInt.zero,
        );
      }).toList();
    } catch (e) {
      state = state.copyWith(error: '扫描失败: $e');
      return [];
    }
  }

  /// 下载 WebDAV 歌曲到本地缓存，返回本地路径
  /// 如果已缓存则直接返回
  Future<String> ensureLocalFile(Song song) async {
    final filePath = song.filePath;
    if (!filePath.startsWith('webdav://')) {
      return filePath; // 本地文件直接返回
    }

    // 解析 webdav://url|remotePath
    final content = filePath.substring('webdav://'.length);
    final pipeIdx = content.indexOf('|');
    if (pipeIdx < 0) throw Exception('无效的 WebDAV 路径');

    final configUrl = content.substring(0, pipeIdx);
    final remotePath = content.substring(pipeIdx + 1);

    // 找到对应的配置
    final config = state.configs.firstWhere(
      (c) => c.url == configUrl,
      orElse: () => throw Exception('WebDAV 配置不存在'),
    );

    state = state.copyWith(downloadProgress: 0.0);

    try {
      final localPath = await _service.downloadToCache(
        config,
        remotePath,
        onProgress: (p) {
          state = state.copyWith(downloadProgress: p);
        },
      );
      state = state.copyWith(clearProgress: true);
      return localPath;
    } catch (e) {
      state = state.copyWith(clearProgress: true);
      rethrow;
    }
  }

  /// 清理缓存
  Future<void> clearCache() async {
    await _service.clearCache();
  }

  /// 获取缓存大小
  Future<int> getCacheSize() async {
    return await _service.getCacheSize();
  }
}
