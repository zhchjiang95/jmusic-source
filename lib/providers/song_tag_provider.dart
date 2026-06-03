import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/services/song_tag_service.dart';

/// 标签筛选状态
class SongTagState {
  /// 所有可用标签
  final List<String> allTags;

  /// 当前选中的筛选标签
  final Set<String> selectedTags;

  /// 是否已加载
  final bool isLoaded;

  const SongTagState({
    this.allTags = const [],
    this.selectedTags = const {},
    this.isLoaded = false,
  });

  SongTagState copyWith({
    List<String>? allTags,
    Set<String>? selectedTags,
    bool? isLoaded,
  }) {
    return SongTagState(
      allTags: allTags ?? this.allTags,
      selectedTags: selectedTags ?? this.selectedTags,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

/// 标签管理 Provider
final songTagProvider =
    NotifierProvider<SongTagNotifier, SongTagState>(SongTagNotifier.new);

class SongTagNotifier extends Notifier<SongTagState> {
  final _service = SongTagService.instance;

  @override
  SongTagState build() {
    _init();
    return const SongTagState();
  }

  Future<void> _init() async {
    await _service.load();
    state = state.copyWith(
      allTags: _service.allTags,
      isLoaded: true,
    );
  }

  /// 刷新状态（从 service 重新读取）
  void refresh() {
    state = state.copyWith(allTags: _service.allTags);
  }

  /// 切换标签选中状态
  void toggleTag(String tag) {
    final selected = Set<String>.from(state.selectedTags);
    if (selected.contains(tag)) {
      selected.remove(tag);
    } else {
      selected.add(tag);
    }
    state = state.copyWith(selectedTags: selected);
  }

  /// 清除所有筛选
  void clearFilter() {
    state = state.copyWith(selectedTags: {});
  }

  /// 创建新标签
  Future<void> createTag(String tag) async {
    _service.createTag(tag);
    await _service.save();
    state = state.copyWith(allTags: _service.allTags);
  }

  /// 删除标签
  Future<void> deleteTag(String tag) async {
    _service.deleteTag(tag);
    final selected = Set<String>.from(state.selectedTags)..remove(tag);
    await _service.save();
    state = state.copyWith(
      allTags: _service.allTags,
      selectedTags: selected,
    );
  }

  /// 重命名标签
  Future<void> renameTag(String oldTag, String newTag) async {
    _service.renameTag(oldTag, newTag);
    final selected = Set<String>.from(state.selectedTags);
    if (selected.remove(oldTag)) {
      selected.add(newTag);
    }
    await _service.save();
    state = state.copyWith(
      allTags: _service.allTags,
      selectedTags: selected,
    );
  }

  /// 给歌曲添加标签
  Future<void> addTagToSong(String filePath, String tag) async {
    _service.addTagToSong(filePath, tag);
    await _service.save();
    state = state.copyWith(allTags: _service.allTags);
  }

  /// 移除歌曲标签
  Future<void> removeTagFromSong(String filePath, String tag) async {
    _service.removeTagFromSong(filePath, tag);
    await _service.save();
  }

  /// 设置歌曲的标签
  Future<void> setTagsForSong(String filePath, List<String> tags) async {
    _service.setTagsForSong(filePath, tags);
    await _service.save();
    state = state.copyWith(allTags: _service.allTags);
  }

  /// 获取歌曲的标签
  List<String> getTagsForSong(String filePath) {
    return _service.getTagsForSong(filePath);
  }

  /// 根据当前选中标签筛选歌曲路径（OR 逻辑：含有任一选中标签即匹配）
  Set<String> getFilteredPaths() {
    if (state.selectedTags.isEmpty) return {};
    return _service.getSongsWithAnyTag(state.selectedTags.toList());
  }
}
