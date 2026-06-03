import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 歌曲标签管理服务
///
/// 维护 filePath 到标签列表的映射，独立于 Rust 端歌曲模型持久化。
/// 支持自定义标签（如"开车"、"工作"、"清晨"等）和多标签筛选。
class SongTagService {
  static SongTagService? _instance;
  static SongTagService get instance {
    _instance ??= SongTagService._();
    return _instance!;
  }

  SongTagService._();

  /// filePath -> tags
  Map<String, List<String>> _songTags = {};

  /// 所有已使用过的标签（有序，按添加时间）
  List<String> _allTags = [];

  bool _loaded = false;
  bool _dirty = false;

  /// 所有标签列表
  List<String> get allTags => List.unmodifiable(_allTags);

  /// 是否已加载
  bool get isLoaded => _loaded;

  /// 加载数据
  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;

        // 加载标签列表
        _allTags = (data['tags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [];

        // 加载歌曲标签映射
        final mappings = data['mappings'] as Map<String, dynamic>? ?? {};
        _songTags = mappings.map((key, value) => MapEntry(
              key,
              (value as List<dynamic>).map((e) => e as String).toList(),
            ));
      }
      _loaded = true;
    } catch (e) {
      debugPrint('[SongTag] 加载失败: $e');
      _songTags = {};
      _allTags = [];
      _loaded = true;
    }
  }

  /// 保存数据
  Future<void> save() async {
    if (!_dirty) return;
    try {
      final file = await _getFile();
      final data = {
        'tags': _allTags,
        'mappings': _songTags,
      };
      await file.writeAsString(jsonEncode(data));
      _dirty = false;
    } catch (e) {
      debugPrint('[SongTag] 保存失败: $e');
    }
  }

  /// 创建新标签
  void createTag(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty || _allTags.contains(trimmed)) return;
    _allTags.add(trimmed);
    _dirty = true;
  }

  /// 删除标签（同时从所有歌曲中移除）
  void deleteTag(String tag) {
    _allTags.remove(tag);
    for (final entry in _songTags.entries) {
      entry.value.remove(tag);
    }
    // 清除空映射
    _songTags.removeWhere((_, tags) => tags.isEmpty);
    _dirty = true;
  }

  /// 重命名标签
  void renameTag(String oldTag, String newTag) {
    final trimmed = newTag.trim();
    if (trimmed.isEmpty || oldTag == trimmed) return;
    if (_allTags.contains(trimmed)) return; // 不允许重名

    final index = _allTags.indexOf(oldTag);
    if (index == -1) return;
    _allTags[index] = trimmed;

    for (final entry in _songTags.entries) {
      final tagIndex = entry.value.indexOf(oldTag);
      if (tagIndex != -1) {
        entry.value[tagIndex] = trimmed;
      }
    }
    _dirty = true;
  }

  /// 给歌曲添加标签
  void addTagToSong(String filePath, String tag) {
    if (!_allTags.contains(tag)) {
      createTag(tag);
    }
    final tags = _songTags.putIfAbsent(filePath, () => []);
    if (!tags.contains(tag)) {
      tags.add(tag);
      _dirty = true;
    }
  }

  /// 移除歌曲的某个标签
  void removeTagFromSong(String filePath, String tag) {
    final tags = _songTags[filePath];
    if (tags != null && tags.remove(tag)) {
      if (tags.isEmpty) {
        _songTags.remove(filePath);
      }
      _dirty = true;
    }
  }

  /// 设置歌曲的标签列表（替换）
  void setTagsForSong(String filePath, List<String> tags) {
    if (tags.isEmpty) {
      _songTags.remove(filePath);
    } else {
      _songTags[filePath] = List.from(tags);
      // 确保所有标签都在 allTags 中
      for (final tag in tags) {
        if (!_allTags.contains(tag)) {
          _allTags.add(tag);
        }
      }
    }
    _dirty = true;
  }

  /// 获取歌曲的标签列表
  List<String> getTagsForSong(String filePath) {
    return _songTags[filePath] ?? [];
  }

  /// 获取含有指定标签的所有歌曲路径
  List<String> getSongsWithTag(String tag) {
    return _songTags.entries
        .where((e) => e.value.contains(tag))
        .map((e) => e.key)
        .toList();
  }

  /// 获取同时含有所有指定标签的歌曲路径（AND 逻辑）
  Set<String> getSongsWithAllTags(List<String> tags) {
    if (tags.isEmpty) return {};
    Set<String>? result;
    for (final tag in tags) {
      final songPaths = _songTags.entries
          .where((e) => e.value.contains(tag))
          .map((e) => e.key)
          .toSet();
      if (result == null) {
        result = songPaths;
      } else {
        result = result.intersection(songPaths);
      }
    }
    return result ?? {};
  }

  /// 获取含有任一指定标签的歌曲路径（OR 逻辑）
  Set<String> getSongsWithAnyTag(List<String> tags) {
    final result = <String>{};
    for (final tag in tags) {
      for (final entry in _songTags.entries) {
        if (entry.value.contains(tag)) {
          result.add(entry.key);
        }
      }
    }
    return result;
  }

  /// 获取标签使用统计 (tag -> count)
  Map<String, int> getTagStats() {
    final stats = <String, int>{};
    for (final tag in _allTags) {
      stats[tag] = 0;
    }
    for (final tags in _songTags.values) {
      for (final tag in tags) {
        stats[tag] = (stats[tag] ?? 0) + 1;
      }
    }
    return stats;
  }

  /// 获取数据文件
  Future<File> _getFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory('${appDir.path}/.jmusic');
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    return File('${dataDir.path}/song_tags.json');
  }
}
