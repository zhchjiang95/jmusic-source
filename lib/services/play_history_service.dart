import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 播放历史记录项
class PlayHistoryEntry {
  final String filePath;
  final String title;
  final String artist;
  final String album;
  final double duration;
  final int playedAt; // Unix 时间戳（毫秒）

  const PlayHistoryEntry({
    required this.filePath,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.playedAt,
  });

  Map<String, dynamic> toJson() => {
        'path': filePath,
        'title': title,
        'artist': artist,
        'album': album,
        'duration': duration,
        'at': playedAt,
      };

  factory PlayHistoryEntry.fromJson(Map<String, dynamic> json) {
    return PlayHistoryEntry(
      filePath: json['path'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      playedAt: json['at'] as int? ?? 0,
    );
  }

  /// 播放时间的 DateTime
  DateTime get playedAtDateTime =>
      DateTime.fromMillisecondsSinceEpoch(playedAt);

  /// 格式化的相对时间
  String get relativeTime {
    final now = DateTime.now();
    final played = playedAtDateTime;
    final diff = now.difference(played);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${played.month}/${played.day}';
  }
}

/// 最近播放历史服务
class PlayHistoryService {
  static PlayHistoryService? _instance;
  static PlayHistoryService get instance {
    _instance ??= PlayHistoryService._();
    return _instance!;
  }

  PlayHistoryService._();

  static const int maxEntries = 200;

  List<PlayHistoryEntry> _entries = [];
  bool _loaded = false;
  bool _dirty = false;

  /// 历史记录列表（最新在前）
  List<PlayHistoryEntry> get entries => List.unmodifiable(_entries);

  /// 是否已加载
  bool get isLoaded => _loaded;

  /// 加载数据
  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> list = jsonDecode(content);
        _entries = list
            .map((e) =>
                PlayHistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      _loaded = true;
    } catch (e) {
      debugPrint('[PlayHistory] 加载失败: $e');
      _entries = [];
      _loaded = true;
    }
  }

  /// 保存数据
  Future<void> save() async {
    if (!_dirty) return;
    try {
      final file = await _getFile();
      final list = _entries.map((e) => e.toJson()).toList();
      await file.writeAsString(jsonEncode(list));
      _dirty = false;
    } catch (e) {
      debugPrint('[PlayHistory] 保存失败: $e');
    }
  }

  /// 记录一次播放
  void recordPlay({
    required String filePath,
    required String title,
    required String artist,
    required String album,
    required double duration,
  }) {
    final entry = PlayHistoryEntry(
      filePath: filePath,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      playedAt: DateTime.now().millisecondsSinceEpoch,
    );

    // 插入到头部
    _entries.insert(0, entry);

    // 限制最大条目数
    if (_entries.length > maxEntries) {
      _entries = _entries.sublist(0, maxEntries);
    }

    _dirty = true;
  }

  /// 清除所有历史
  void clear() {
    _entries.clear();
    _dirty = true;
  }

  /// 获取数据文件
  Future<File> _getFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory('${appDir.path}/.jmusic');
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    return File('${dataDir.path}/play_history.json');
  }
}
