import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/song_tag_provider.dart';
import 'package:jmusic/services/song_tag_service.dart';

/// 歌曲标签编辑面板
class SongTagSheet extends ConsumerStatefulWidget {
  final String filePath;
  final String songTitle;

  const SongTagSheet({
    super.key,
    required this.filePath,
    required this.songTitle,
  });

  /// 显示标签编辑面板
  static void show(BuildContext context, String filePath, String songTitle) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SongTagSheet(filePath: filePath, songTitle: songTitle),
    );
  }

  @override
  ConsumerState<SongTagSheet> createState() => _SongTagSheetState();
}

class _SongTagSheetState extends ConsumerState<SongTagSheet> {
  final _newTagController = TextEditingController();
  late List<String> _songTags;

  @override
  void initState() {
    super.initState();
    _songTags = List.from(
      SongTagService.instance.getTagsForSong(widget.filePath),
    );
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tagState = ref.watch(songTagProvider);
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽手柄
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 标题
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Icon(Icons.label_outline_rounded,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '标签 — ${widget.songTitle}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 当前歌曲的标签
          if (_songTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _songTags.map((tag) {
                    return Chip(
                      label: Text(
                        tag,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                      backgroundColor:
                          theme.colorScheme.primary.withValues(alpha: 0.25),
                      side: BorderSide(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.4),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      deleteIconColor: Colors.white54,
                      onDeleted: () => _removeTag(tag),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ),
            ),

          const Divider(
            color: Colors.white12,
            height: 24,
            indent: 16,
            endIndent: 16,
          ),

          // 新建标签输入
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _newTagController,
                      style:
                          const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '输入新标签名...',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 0),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _createAndAddTag(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: ElevatedButton(
                    onPressed: _createAndAddTag,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('添加', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 所有可用标签（点击即添加/移除）
          if (tagState.allTags.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '所有标签（点击切换）',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: tagState.allTags.map((tag) {
                    final isActive = _songTags.contains(tag);
                    return GestureDetector(
                      onLongPress: () => _showTagOptions(tag),
                      child: FilterChip(
                        label: Text(
                          tag,
                          style: TextStyle(
                            color: isActive ? Colors.white : Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                        selected: isActive,
                        selectedColor:
                            theme.colorScheme.primary.withValues(alpha: 0.3),
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        side: BorderSide(
                          color: isActive
                              ? theme.colorScheme.primary.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.1),
                        ),
                        checkmarkColor: theme.colorScheme.primary,
                        onSelected: (selected) {
                          if (selected) {
                            _addTag(tag);
                          } else {
                            _removeTag(tag);
                          }
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _addTag(String tag) {
    if (!_songTags.contains(tag)) {
      setState(() => _songTags.add(tag));
      ref.read(songTagProvider.notifier).addTagToSong(widget.filePath, tag);
    }
  }

  void _removeTag(String tag) {
    setState(() => _songTags.remove(tag));
    ref.read(songTagProvider.notifier).removeTagFromSong(widget.filePath, tag);
  }

  void _createAndAddTag() {
    final tag = _newTagController.text.trim();
    if (tag.isEmpty) return;
    _newTagController.clear();
    _addTag(tag);
  }

  void _showTagOptions(String tag) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2A2A3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.white70, size: 20),
                title: Text('重命名 "$tag"',
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRenameDialog(tag);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Colors.redAccent, size: 20),
                title: Text('删除 "$tag"',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteTag(tag);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRenameDialog(String oldTag) {
    final controller = TextEditingController(text: oldTag);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A3A),
        title: const Text('重命名标签',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final newTag = controller.text.trim();
              if (newTag.isNotEmpty && newTag != oldTag) {
                ref.read(songTagProvider.notifier).renameTag(oldTag, newTag);
                setState(() {
                  final idx = _songTags.indexOf(oldTag);
                  if (idx != -1) _songTags[idx] = newTag;
                });
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _deleteTag(String tag) {
    ref.read(songTagProvider.notifier).deleteTag(tag);
    setState(() => _songTags.remove(tag));
  }
}
