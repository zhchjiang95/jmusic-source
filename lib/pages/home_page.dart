import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/src/rust/models/song.dart';
import 'package:jmusic/src/rust/api/metadata.dart' as rust_metadata;
import 'package:jmusic/widgets/mini_player.dart';

/// 主页 - 歌曲库列表
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

  @override
  void dispose() {
    _focusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 键盘事件处理
  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    // 搜索框聚焦时不处理快捷键
    if (FocusManager.instance.primaryFocus != _focusNode) return;

    final notifier = ref.read(playerProvider.notifier);
    final player = ref.read(playerProvider);

    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        if (player.currentSong != null) {
          notifier.togglePlayPause();
        } else {
          // 用当前搜索过滤后的列表播放
          final songs = _getFilteredSongs();
          if (songs.isNotEmpty) {
            notifier.setPlaylist(songs);
            notifier.playSongAt(Random().nextInt(songs.length));
          }
        }
      case LogicalKeyboardKey.arrowRight:
        if (player.currentSong != null) notifier.next();
      case LogicalKeyboardKey.arrowLeft:
        if (player.currentSong != null) notifier.previous();
      default:
        break;
    }
  }

  /// 获取当前搜索过滤后的歌曲列表
  List<Song> _getFilteredSongs() {
    final songs = ref.read(libraryProvider).songs;
    if (_searchQuery.isEmpty) return songs;
    final q = _searchQuery.toLowerCase();
    return songs
        .where(
          (s) =>
              s.title.toLowerCase().contains(q) ||
              s.artist.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryProvider);
    final playerState = ref.watch(playerProvider);
    final theme = Theme.of(context);

    // 根据搜索关键词过滤歌曲
    final filteredSongs = _searchQuery.isEmpty
        ? libraryState.songs
        : libraryState.songs.where((song) {
            final q = _searchQuery.toLowerCase();
            return song.title.toLowerCase().contains(q) ||
                song.artist.toLowerCase().contains(q);
          }).toList();

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
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
                        '${filteredSongs.length}/${libraryState.songs.length} 首',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    if (playerState.currentSong != null)
                      IconButton(
                        onPressed: () {
                          final currentSong = playerState.currentSong;
                          if (currentSong == null) return;

                          void scrollToTarget(int index) {
                            if (!_scrollController.hasClients) return;
                            final targetOffset = index * 44.0;
                            final viewportHeight =
                                _scrollController.position.viewportDimension;
                            final maxScroll =
                                _scrollController.position.maxScrollExtent;
                            var offset =
                                targetOffset - viewportHeight / 2 + 22.0;
                            if (offset < 0) offset = 0;
                            if (offset > maxScroll) offset = maxScroll;

                            _scrollController.animateTo(
                              offset,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }

                          final index = filteredSongs.indexWhere(
                            (s) => s.filePath == currentSong.filePath,
                          );
                          if (index != -1) {
                            scrollToTarget(index);
                          } else {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                            Future.delayed(
                              const Duration(milliseconds: 100),
                              () {
                                final realIndex = libraryState.songs.indexWhere(
                                  (s) => s.filePath == currentSong.filePath,
                                );
                                if (realIndex != -1) scrollToTarget(realIndex);
                              },
                            );
                          }
                        },
                        icon: Icon(
                          Icons.location_on,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        tooltip: '定位当前播放',
                      ),
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

              // 搜索框
              if (libraryState.songs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '搜索歌曲、歌手...',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.3,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 18,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                  // 清除搜索后把焦点还给主页
                                  _focusNode.requestFocus();
                                },
                                icon: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 12,
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.onSurface.withValues(
                          alpha: 0.06,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                      },
                      // 输入完成后焦点还给主页（恢复快捷键）
                      onEditingComplete: () => _focusNode.requestFocus(),
                    ),
                  ),
                ),

              // 歌曲列表
              Expanded(
                child: libraryState.songs.isEmpty
                    ? _buildEmptyState(context, ref, libraryState)
                    : _buildSongList(
                        context,
                        ref,
                        filteredSongs,
                        libraryState,
                        playerState,
                      ),
              ),

              // 底部迷你播放栏
              if (playerState.currentSong != null) const MiniPlayer(),
            ],
          ),
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
    List<Song> songs,
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
          child: songs.isEmpty
              ? Center(
                  child: Text(
                    '未找到匹配歌曲',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      fontSize: 14,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: songs.length,
                  itemExtent: 44,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    final isCurrentSong =
                        playerState.currentSong?.filePath == song.filePath;

                    return GestureDetector(
                      onSecondaryTapUp: (details) {
                        _showContextMenu(
                          context,
                          ref,
                          details.globalPosition,
                          song,
                        );
                      },
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            ref
                                .read(playerProvider.notifier)
                                .setPlaylist(songs);
                            ref
                                .read(playerProvider.notifier)
                                .playSongAt(index);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: isCurrentSong
                                  ? theme.colorScheme.primary.withValues(
                                      alpha: 0.12,
                                    )
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                    style: TextStyle(
                                      color: dimColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                // 文件大小
                                SizedBox(
                                  width: 60,
                                  child: Text(
                                    _formatFileSize(song.fileSize.toInt()),
                                    style: TextStyle(
                                      color: dimColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                // 格式
                                SizedBox(
                                  width: 50,
                                  child: Text(
                                    song.format.toUpperCase(),
                                    style: TextStyle(
                                      color: dimColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                // 时长
                                SizedBox(
                                  width: 48,
                                  child: Text(
                                    _formatDuration(song.duration),
                                    style: TextStyle(
                                      color: dimColor,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
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

  /// 右键菜单
  void _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
    Song song,
  ) {
    final theme = Theme.of(context);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: const Color(0xFF2A2A3E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'edit',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.edit, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Text('编辑信息', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'import_lyrics',
          height: 36,
          child: Row(
            children: [
              Icon(
                Icons.lyrics_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text('导入歌词', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'edit_cover',
          height: 36,
          child: Row(
            children: [
              Icon(
                Icons.image_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text('修改专辑图', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'edit') {
        _showEditDialog(context, ref, song);
      } else if (value == 'import_lyrics') {
        _showImportLyricsDialog(context, ref, song);
      } else if (value == 'edit_cover') {
        _showEditCoverDialog(context, ref, song);
      }
    });
  }

  /// 编辑歌曲信息对话框
  void _showEditDialog(BuildContext context, WidgetRef ref, Song song) {
    final titleCtrl = TextEditingController(text: song.title);
    final artistCtrl = TextEditingController(text: song.artist);
    final albumCtrl = TextEditingController(text: song.album);
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          '编辑歌曲信息',
          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField('标题', titleCtrl, theme),
              const SizedBox(height: 12),
              _buildTextField('歌手', artistCtrl, theme),
              const SizedBox(height: 12),
              _buildTextField('专辑', albumCtrl, theme),
              const SizedBox(height: 8),
              // 文件路径提示
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  song.filePath.split('/').last,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              '取消',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref
                    .read(libraryProvider.notifier)
                    .updateSongInfo(
                      filePath: song.filePath,
                      title: titleCtrl.text.trim(),
                      artist: artistCtrl.text.trim(),
                      album: albumCtrl.text.trim(),
                    );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 导入歌词对话框
  void _showImportLyricsDialog(BuildContext context, WidgetRef ref, Song song) {
    final theme = Theme.of(context);
    final idController = TextEditingController();
    final textController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.lyrics_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '导入歌词 - ${song.title}',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: DefaultTabController(
                length: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TabBar(
                      labelColor: theme.colorScheme.primary,
                      unselectedLabelColor:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      indicatorColor: theme.colorScheme.primary,
                      dividerColor: Colors.transparent,
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      tabs: const [Tab(text: '网易云在线'), Tab(text: '手动输入')],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 240,
                      child: TabBarView(
                        children: [
                          // 模式1：网易云在线获取
                          Builder(
                            builder: (context) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '请输入网易云音乐歌曲 ID：',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: idController,
                                  autofocus: true,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: '例如：85625',
                                    filled: true,
                                    fillColor: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.06),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (isLoading)
                                  const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                else
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        String input = idController.text.trim();
                                        if (input.isEmpty) return;

                                        // 尝试从 URL 中提取 ID
                                        String finalId = input;
                                        if (input.contains('id=')) {
                                          try {
                                            final uri = Uri.parse(input);
                                            final idFromQuery =
                                                uri.queryParameters['id'];
                                            if (idFromQuery != null) {
                                              finalId = idFromQuery;
                                            }
                                          } catch (_) {
                                            // 解析失败则按原样处理
                                          }
                                        }

                                        setDialogState(() => isLoading = true);
                                        try {
                                          final lrc = await rust_metadata
                                              .getNeteaseLyrics(id: finalId);

                                          final buffer = StringBuffer();
                                          for (final line in lrc.lines) {
                                            final totalMs = line.timeMs.toInt();
                                            final minutes = totalMs ~/ 60000;
                                            final seconds =
                                                (totalMs % 60000) / 1000;
                                            final timeStr =
                                                "${minutes.toString().padLeft(2, '0')}:${seconds.toStringAsFixed(2).padLeft(5, '0')}";
                                            buffer.writeln(
                                              "[$timeStr]${line.text}",
                                            );
                                          }
                                          textController.text =
                                              buffer.toString();
                                          if (context.mounted) {
                                            DefaultTabController.of(context)
                                                .animateTo(1);
                                          }
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text('获取失败: $e'),
                                              ),
                                            );
                                          }
                                        } finally {
                                          setDialogState(
                                            () => isLoading = false,
                                          );
                                        }
                                      },
                                      icon:
                                          const Icon(Icons.download, size: 16),
                                      label: const Text('获取歌词'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // 模式2：手动输入
                          Column(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: textController,
                                  maxLines: null,
                                  expands: true,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                  ),
                                  decoration: InputDecoration(
                                    hintText:
                                        '请在此粘贴 LRC 格式歌词...\n[00:00.00] 歌词内容',
                                    filled: true,
                                    fillColor: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.06),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.all(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  '取消',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              FilledButton(
                onPressed: () async {
                  final lyrics = textController.text.trim();
                  if (lyrics.isEmpty) return;
                  Navigator.of(ctx).pop();
                  try {
                    await ref
                        .read(libraryProvider.notifier)
                        .saveAllMetadataAndUpdate(
                          song: song,
                          lyricsText: lyrics,
                        );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('歌词已成功导入并内嵌')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('保存失败: $e')),
                      );
                    }
                  }
                },
                child: const Text('保存并内嵌'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 修改专辑图对话框
  void _showEditCoverDialog(BuildContext context, WidgetRef ref, Song song) {
    final theme = Theme.of(context);
    final urlController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.image_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '修改专辑图 - ${song.title}',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '输入图片网络地址：',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: urlController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'http://...',
                      filled: true,
                      fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      '或',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isLoading ? null : () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                        );
                        if (result != null && result.files.single.path != null) {
                          setDialogState(() => isLoading = true);
                          try {
                            final file = File(result.files.single.path!);
                            final bytes = await file.readAsBytes();
                            Navigator.of(ctx).pop();
                            await ref
                                .read(libraryProvider.notifier)
                                .saveAllMetadataAndUpdate(
                                  song: song,
                                  coverData: bytes,
                                );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('专辑图已成功更新')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('保存失败: $e')),
                              );
                            }
                          } finally {
                            if (context.mounted) {
                              setDialogState(() => isLoading = false);
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('选择本地图片'),
                    ),
                  ),
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  '取消',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              FilledButton(
                onPressed: isLoading ? null : () async {
                  final url = urlController.text.trim();
                  if (url.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请输入图片地址或选择本地图片')),
                    );
                    return;
                  }
                  setDialogState(() => isLoading = true);
                  try {
                    final response = await http.get(Uri.parse(url));
                    if (response.statusCode == 200) {
                      final bytes = response.bodyBytes;
                      Navigator.of(ctx).pop();
                      await ref
                          .read(libraryProvider.notifier)
                          .saveAllMetadataAndUpdate(
                            song: song,
                            coverData: bytes,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('专辑图已成功更新')),
                        );
                      }
                    } else {
                      throw Exception('下载失败，状态码: ${response.statusCode}');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('下载或保存失败: $e')),
                      );
                    }
                    setDialogState(() => isLoading = false);
                  }
                },
                child: const Text('保存网络图片'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 构建编辑字段
  Widget _buildTextField(
    String label,
    TextEditingController controller,
    ThemeData theme,
  ) {
    return TextField(
      controller: controller,
      style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 13,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        filled: true,
        fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
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
