import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/providers/macos_status_bar.dart';
import 'package:jmusic/src/rust/models/song.dart';
import 'package:jmusic/src/rust/api/metadata.dart' as rust_metadata;
import 'package:jmusic/src/rust/api/scanner.dart' as rust_scanner;
import 'package:jmusic/widgets/mini_player.dart';
import 'package:jmusic/widgets/web_remote_sheet.dart';
import 'package:jmusic/widgets/webdav_sheet.dart';
import 'package:jmusic/providers/webdav_provider.dart';
import 'package:jmusic/pages/play_stats_page.dart';
import 'package:jmusic/pages/listening_report_page.dart';
import 'package:jmusic/pages/listening_calendar_page.dart';
import 'package:jmusic/pages/queue_history_page.dart';
import 'package:jmusic/pages/achievements_page.dart';
import 'package:jmusic/providers/song_tag_provider.dart';
import 'package:jmusic/widgets/song_tag_sheet.dart';
import 'package:jmusic/widgets/export_dialog.dart';
import 'package:jmusic/widgets/album_grid_view.dart';
import 'package:jmusic/widgets/artist_grid_view.dart';
import 'package:jmusic/widgets/playing_wave_indicator.dart';


/// 主页 - 歌曲库列表
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  int _currentViewIndex = 0; // 0: 单曲, 1: 专辑, 2: 歌手


  @override
  void initState() {
    super.initState();
    // 注册全局键盘事件处理，确保焦点不在搜索框时也能响应快捷键
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _searchFocusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 全局键盘事件处理。返回 true 表示已处理（阻止继续传播）。
  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!mounted) return false;
    // 当前路由不在最前（比如跳到了 PlayerPage / 全屏歌词页）时不处理，
    // 避免与上层页面的 CallbackShortcuts 重复触发，导致快捷键互相抵消。
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null && !modalRoute.isCurrent) return false;
    // 搜索框聚焦时（或任何可编辑文本聚焦时）不拦截，避免影响输入
    if (_searchFocusNode.hasFocus) return false;
    final focused = FocusManager.instance.primaryFocus;
    final focusedWidget = focused?.context?.widget;
    if (focusedWidget is EditableText) return false;

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
        return true;
      case LogicalKeyboardKey.arrowRight:
        if (player.currentSong != null) {
          notifier.next();
          return true;
        }
        return false;
      case LogicalKeyboardKey.arrowLeft:
        if (player.currentSong != null) {
          notifier.previous();
          return true;
        }
        return false;
      default:
        return false;
    }
  }

  /// 获取当前搜索过滤后的歌曲列表
  List<Song> _getFilteredSongs() {
    final songs = [
      ...ref.read(libraryProvider).songs,
      ...ref.read(webDavProvider).songs,
    ];

    // 标签筛选
    final tagState = ref.read(songTagProvider);
    List<Song> filtered = songs;
    if (tagState.selectedTags.isNotEmpty) {
      final matchedPaths =
          ref.read(songTagProvider.notifier).getFilteredPaths();
      filtered = filtered
          .where((s) => matchedPaths.contains(s.filePath))
          .toList();
    }

    // 文本搜索
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where(
            (s) =>
                s.title.toLowerCase().contains(q) ||
                s.artist.toLowerCase().contains(q) ||
                s.album.toLowerCase().contains(q),
          )
          .toList();
    }

    return filtered;
  }

  /// 更新搜索关键词，并把过滤后的列表同步给播放器，
  /// 这样 next()/previous()/自动播放都使用当前可见的列表。
  void _updateSearchQuery(String query) {
    setState(() => _searchQuery = query);
    ref.read(playerProvider.notifier).setPlaylist(_getFilteredSongs());
  }

  /// 用专辑名搜索：把专辑名填充到搜索框并触发过滤
  void _searchByAlbum(String album) {
    if (album.isEmpty) return;
    _searchController.text = album;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: album.length),
    );
    _updateSearchQuery(album);
    // 滚回顶部，便于查看搜索结果
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  /// 用歌手名搜索：把歌手名填充到搜索框并触发过滤
  void _searchByArtist(String artist) {
    if (artist.isEmpty) return;
    _searchController.text = artist;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: artist.length),
    );
    _updateSearchQuery(artist);
    // 滚回顶部，便于查看搜索结果
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }


  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryProvider);
    final webDavState = ref.watch(webDavProvider);
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final tagState = ref.watch(songTagProvider);
    final theme = Theme.of(context);

    // 合并本地 + WebDAV 歌曲
    final allSongs = [...libraryState.songs, ...webDavState.songs];

    // 在 macOS 平台主动激活菜单栏歌词控制器（懒加载 Provider 必须有人 watch 才会 build）
    if (Platform.isMacOS) {
      ref.watch(macosStatusBarControllerProvider);
    }

    // 监听播放错误
    ref.listen<String?>(playerProvider.select((s) => s.error), (prev, next) {
      if (next != null && next != prev) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next)),
        );
      }
    });

    // 根据标签 + 搜索关键词过滤歌曲
    List<Song> filteredSongs = allSongs;

    // 标签筛选
    if (tagState.selectedTags.isNotEmpty) {
      final matchedPaths =
          ref.read(songTagProvider.notifier).getFilteredPaths();
      filteredSongs = filteredSongs
          .where((s) => matchedPaths.contains(s.filePath))
          .toList();
    }

    // 文本搜索
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filteredSongs = filteredSongs
          .where((song) =>
              song.title.toLowerCase().contains(q) ||
              song.artist.toLowerCase().contains(q) ||
              song.album.toLowerCase().contains(q))
          .toList();
    }

    final leftPadding = Platform.isMacOS ? 84.0 : 20.0;
    final topPadding = Platform.isMacOS ? 12.0 : 8.0;

    return Scaffold(
      backgroundColor: const Color(0xFF08080E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 统一空间氛围底层光影（与播放页共享视觉语言）
          _buildAmbientBackground(theme),

          // 2. 主体内容层
          SafeArea(
            top: false, // 沉浸式窗口下由自定义顶栏接管顶部边距
            child: Column(
              children: [
                // 沉浸式一体化顶栏
                _buildUnifiedHeaderBar(
                  context: context,
                  ref: ref,
                  theme: theme,
                  libraryState: libraryState,
                  allSongs: allSongs,
                  filteredSongs: filteredSongs,
                  leftPadding: leftPadding,
                  topPadding: topPadding,
                ),

                // 标签筛选栏 (仅在单曲视图下显示)
                if (allSongs.isNotEmpty && _currentViewIndex == 0)
                  _buildTagFilterBar(theme),

                // 列表显示区域（占满底部）与悬浮控制台
                Expanded(
                  child: Stack(
                    children: [
                      // 1. 列表主体（铺满底层视口到底部）
                      Positioned.fill(
                        child: allSongs.isEmpty
                            ? _buildEmptyState(context, ref, libraryState)
                            : _buildCurrentView(
                                context,
                                ref,
                                filteredSongs,
                                libraryState,
                                currentSong,
                                isPlaying,
                              ),
                      ),

                      // 2. 悬浮定位按钮（位于悬浮控制台上方的右下角，仅在单曲视图下显示）
                      if (currentSong != null && _currentViewIndex == 0)
                        Positioned(
                          right: 24,
                          bottom: 92,
                          child: _buildLocateButton(
                            context,
                            filteredSongs,
                            libraryState,
                            currentSong,
                          ),
                        ),

                      // 3. 底部悬浮玻璃磨砂迷你播放控制台
                      if (currentSong != null)
                        const Positioned(
                          left: 20,
                          right: 20,
                          bottom: 14,
                          child: MiniPlayer(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建与播放页同源的空间氛围微光背景（采用全不透明色值插值，消除对角线明暗分界断层）
  Widget _buildAmbientBackground(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.35, 0.72, 1.0],
                colors: [
                  Color.lerp(const Color(0xFF0B0B14), primary, 0.14)!,
                  Color.lerp(const Color(0xFF0A0A12), primary, 0.08)!,
                  Color.lerp(const Color(0xFF08080F), primary, 0.03)!,
                  const Color(0xFF07070C),
                ],
              ),
            ),
          ),
          Positioned(
            right: -160,
            top: -140,
            width: 560,
            height: 560,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primary.withValues(alpha: 0.08),
                    primary.withValues(alpha: 0.03),
                    primary.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 沉浸式一体化顶栏（Unified Header Bar，毛玻璃胶囊风格）
  Widget _buildUnifiedHeaderBar({
    required BuildContext context,
    required WidgetRef ref,
    required ThemeData theme,
    required LibraryState libraryState,
    required List<Song> allSongs,
    required List<Song> filteredSongs,
    required double leftPadding,
    required double topPadding,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: 8),
      child: SizedBox(
        height: 38,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 左右两侧功能区域
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 左侧：交通灯避让区 + 视图切换按钮组（单曲 / 专辑 / 歌手）
                Padding(
                  padding: EdgeInsets.only(left: leftPadding),
                  child: allSongs.isNotEmpty
                      ? _buildViewSelector(theme)
                      : const SizedBox.shrink(),
                ),

                const Spacer(),

                // 右侧：歌曲统计徽章 + 扫描目录 + 更多设置
                if (allSongs.isNotEmpty) ...[
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      '${filteredSongs.length} / ${allSongs.length} 首',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // 扫描音乐目录按钮（圆形毛玻璃按钮）
                Tooltip(
                  message: '添加音乐目录',
                  child: InkWell(
                    onTap: libraryState.isScanning
                        ? null
                        : () => _scanDirectory(ref),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 0.8,
                        ),
                      ),
                      child: libraryState.isScanning
                          ? SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            )
                          : const Icon(
                              Icons.folder_open_rounded,
                              color: Colors.white70,
                              size: 18,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 更多选项菜单
                _buildMoreMenu(context, theme),
                const SizedBox(width: 20),
              ],
            ),

            // 中间水平绝对居中：毛玻璃胶囊搜索框
            if (allSongs.isNotEmpty)
              Center(
                child: SizedBox(
                  width: 300,
                  height: 34,
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText: '搜索音乐、歌手、专辑...',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.38),
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _searchController.clear();
                                _updateSearchQuery('');
                                _searchFocusNode.unfocus();
                              },
                              icon: Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: Colors.white.withValues(alpha: 0.5),
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
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.10),
                          width: 0.8,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.55,
                          ),
                          width: 1.0,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) => _updateSearchQuery(value),
                    onSubmitted: (_) => _searchFocusNode.unfocus(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 更多操作下拉菜单
  Widget _buildMoreMenu(BuildContext context, ThemeData theme) {
    return PopupMenuButton<String>(
      tooltip: '更多',
      color: const Color(0xFF1A1A26),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.10),
          width: 0.8,
        ),
      ),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 0.8,
          ),
        ),
        child: const Icon(
          Icons.more_horiz_rounded,
          color: Colors.white70,
          size: 18,
        ),
      ),
      onSelected: (value) {
        switch (value) {
          case 'queue':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const QueueHistoryPage(),
              ),
            );
          case 'stats':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PlayStatsPage(),
              ),
            );
          case 'report':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ListeningReportPage(),
              ),
            );
          case 'calendar':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ListeningCalendarPage(),
              ),
            );
          case 'achievements':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AchievementsPage(),
              ),
            );
          case 'remote':
            WebRemoteSheet.show(context);
          case 'webdav':
            WebDavSheet.show(context);
          case 'settings':
            _showMacosSettingsDialog(context);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'queue',
          child: ListTile(
            leading: Icon(Icons.queue_music_rounded,
                color: Colors.white70, size: 20),
            title: Text('队列与历史',
                style: TextStyle(
                    color: Colors.white, fontSize: 14)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'stats',
          child: ListTile(
            leading: Icon(Icons.bar_chart,
                color: Colors.white70, size: 20),
            title: Text('播放统计',
                style: TextStyle(
                    color: Colors.white, fontSize: 14)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'report',
          child: ListTile(
            leading: Icon(Icons.auto_awesome,
                color: Colors.white70, size: 20),
            title: Text('听歌报告',
                style: TextStyle(
                    color: Colors.white, fontSize: 14)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'calendar',
          child: ListTile(
            leading: Icon(Icons.calendar_month,
                color: Colors.white70, size: 20),
            title: Text('听歌日历',
                style: TextStyle(
                    color: Colors.white, fontSize: 14)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'achievements',
          child: ListTile(
            leading: Icon(Icons.emoji_events_outlined,
                color: Colors.white70, size: 20),
            title: Text('听歌成就',
                style: TextStyle(
                    color: Colors.white, fontSize: 14)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'remote',
          child: ListTile(
            leading: Icon(Icons.wifi_tethering,
                color: Colors.white70, size: 20),
            title: Text('Web 遥控',
                style: TextStyle(
                    color: Colors.white, fontSize: 14)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'webdav',
          child: ListTile(
            leading: Icon(Icons.cloud_outlined,
                color: Colors.white70, size: 20),
            title: Text('WebDAV 音乐源',
                style: TextStyle(
                    color: Colors.white, fontSize: 14)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (Platform.isMacOS)
          const PopupMenuItem(
            value: 'settings',
            child: ListTile(
              leading: Icon(Icons.settings_outlined,
                  color: Colors.white70, size: 20),
              title: Text('设置',
                  style: TextStyle(
                      color: Colors.white, fontSize: 14)),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  /// 视图切换胶囊（毛玻璃分段按钮）
  Widget _buildViewSelector(ThemeData theme) {
    return Container(
      height: 32,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSelectorTab(0, '单曲', theme),
          _buildSelectorTab(1, '专辑', theme),
          _buildSelectorTab(2, '歌手', theme),
        ],
      ),
    );
  }

  Widget _buildSelectorTab(int index, String label, ThemeData theme) {
    final isSelected = _currentViewIndex == index;
    return InkWell(
      onTap: () {
        setState(() {
          _currentViewIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.24)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: isSelected
              ? Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.45),
                  width: 0.8,
                )
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.white60,
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentView(
    BuildContext context,
    WidgetRef ref,
    List<Song> filteredSongs,
    LibraryState libraryState,
    Song? currentSong,
    bool isPlaying,
  ) {
    final bottomPadding = currentSong != null ? 88.0 : 16.0;
    switch (_currentViewIndex) {
      case 1:
        return AlbumGridView(
          searchQuery: _searchQuery,
          bottomPadding: bottomPadding,
        );
      case 2:
        return ArtistGridView(
          searchQuery: _searchQuery,
          bottomPadding: bottomPadding,
        );
      case 0:
      default:
        return _buildSongList(
          context,
          ref,
          filteredSongs,
          libraryState,
          currentSong,
          isPlaying,
        );
    }
  }

  /// 标签筛选栏
  Widget _buildTagFilterBar(ThemeData theme) {
    return Consumer(
      builder: (context, ref, _) {
        final tagState = ref.watch(songTagProvider);
        if (tagState.allTags.isEmpty) return const SizedBox.shrink();

        return SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // 清除筛选按钮（选中标签时显示）
                if (tagState.selectedTags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      avatar: const Icon(Icons.close, size: 12, color: Colors.white54),
                      label: const Text('清除',
                          style: TextStyle(color: Colors.white54, fontSize: 11)),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      onPressed: () {
                        ref.read(songTagProvider.notifier).clearFilter();
                        ref.read(playerProvider.notifier).setPlaylist(_getFilteredSongs());
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
                // 标签 Chips
                ...tagState.allTags.map((tag) {
                  final isSelected = tagState.selectedTags.contains(tag);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(
                        tag,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor:
                          theme.colorScheme.primary.withValues(alpha: 0.3),
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      side: BorderSide(
                        color: isSelected
                            ? theme.colorScheme.primary.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                      checkmarkColor: theme.colorScheme.primary,
                      showCheckmark: false,
                      onSelected: (_) {
                        ref.read(songTagProvider.notifier).toggleTag(tag);
                        // 切换标签后同步播放列表
                        Future.microtask(() {
                          ref.read(playerProvider.notifier).setPlaylist(_getFilteredSongs());
                        });
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 悬浮定位按钮（中心实心圆 + 外圆环）
  Widget _buildLocateButton(
    BuildContext context,
    List<Song> filteredSongs,
    LibraryState libraryState,
    Song? currentSong,
  ) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return GestureDetector(
      onTap: () {
        if (currentSong == null) return;

        void scrollToTarget(int index) {
          if (!_scrollController.hasClients) return;
          final targetOffset = index * 50.0;
          final viewportHeight =
              _scrollController.position.viewportDimension;
          final maxScroll = _scrollController.position.maxScrollExtent;
          var offset = targetOffset - viewportHeight / 2 + 25.0;
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
          _updateSearchQuery('');
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
      child: Tooltip(
        message: '定位当前播放',
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF141422).withValues(alpha: 0.88),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.45),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            Icons.my_location_rounded,
            size: 17,
            color: primaryColor,
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

  /// 格式化文件大小
  static String _formatSongFileSize(BigInt bytes) {
    final b = bytes.toInt();
    if (b <= 0) return '-';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) {
      return '${(b / 1024).toStringAsFixed(1)} KB';
    }
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 歌曲列表（先锋杂志排版自适应表格布局）
  Widget _buildSongList(
    BuildContext context,
    WidgetRef ref,
    List<Song> songs,
    LibraryState libraryState,
    Song? currentSong,
    bool isPlaying,
  ) {
    final theme = Theme.of(context);
    final dimColor = Colors.white.withValues(alpha: 0.45);
    final headerStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.42),
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // 当宽度 >= 720 时启用宽屏桌面表格模式
        final isWide = constraints.maxWidth >= 720;

        return Column(
          children: [
            // 先锋杂志风表头
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 8, 26, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: isWide ? 42 : 36,
                    child: Text('#', style: headerStyle),
                  ),
                  if (isWide) ...[
                    Expanded(
                      flex: 4,
                      child: Text('标题', style: headerStyle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Text('歌手', style: headerStyle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Text('专辑', style: headerStyle),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 74,
                      child: Text('大小', style: headerStyle),
                    ),
                  ] else ...[
                    Expanded(
                      flex: 4,
                      child: Text('标题 / 歌手', style: headerStyle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: Text('专辑', style: headerStyle),
                    ),
                  ],
                  SizedBox(
                    width: isWide ? 64 : 52,
                    child: Text('规格', style: headerStyle),
                  ),
                  SizedBox(
                    width: isWide ? 54 : 48,
                    child: Text(
                      '时长',
                      style: headerStyle,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  if (isWide) const SizedBox(width: 80), // 占位给右侧快捷操作栏
                ],
              ),
            ),
            // 渐变微光分割线（与播放页统一风格）
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.0),
                    Colors.white.withValues(alpha: 0.08),
                    Colors.white.withValues(alpha: 0.08),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.1, 0.9, 1.0],
                ),
              ),
            ),

            // 歌曲行
            Expanded(
              child: songs.isEmpty
                  ? Center(
                      child: Text(
                        '未找到匹配歌曲',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        12,
                        6,
                        12,
                        currentSong != null ? 96.0 : 20.0,
                      ),
                      itemCount: songs.length,
                      itemExtent: 50,
                      itemBuilder: (context, index) {
                        final song = songs[index];
                        final isCurrentSong =
                            currentSong?.filePath == song.filePath;

                        return _SongListTile(
                          key: ValueKey(song.filePath),
                          index: index,
                          song: song,
                          isWide: isWide,
                          isCurrentSong: isCurrentSong,
                          isPlaying: isCurrentSong && isPlaying,
                          dimColor: dimColor,
                          onTap: () {
                            ref
                                .read(playerProvider.notifier)
                                .setPlaylist(songs);
                            ref.read(playerProvider.notifier).playSongAt(index);
                          },
                          onSecondaryTapUp: (details) {
                            _showContextMenu(
                              context,
                              ref,
                              details.globalPosition,
                              song,
                            );
                          },
                          onLongPressStart: (details) {
                            _showContextMenu(
                              context,
                              ref,
                              details.globalPosition,
                              song,
                            );
                          },
                          onArtistTap: (artist) => _searchByArtist(artist),
                          onAlbumTap: (album) => _searchByAlbum(album),
                          onPlayNext: () {
                            ref
                                .read(playerProvider.notifier)
                                .playNextInQueue(song);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('下一首播放: ${song.title}'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          onAddToQueue: () {
                            ref.read(playerProvider.notifier).addToQueue(song);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('已添加到队列: ${song.title}'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          onMoreTap: (position) {
                            _showContextMenu(context, ref, position, song);
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
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
          value: 'play_next',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.playlist_play_rounded, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Text('下一首播放', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'add_queue',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.playlist_add_rounded, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Text('添加到队列', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem(
          value: 'info',
          height: 36,
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text('查看音乐信息', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
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
        PopupMenuItem(
          value: 'tags',
          height: 36,
          child: Row(
            children: [
              Icon(
                Icons.label_outline_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text('标签管理', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'export',
          height: 36,
          child: Row(
            children: [
              Icon(
                Icons.transform_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text('音频格式转换...', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        const PopupMenuItem(
          value: 'delete',
          height: 36,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: Colors.redAccent,
              ),
              SizedBox(width: 8),
              Text(
                '删除歌曲 (从本地硬盘移除)',
                style: TextStyle(fontSize: 13, color: Colors.redAccent),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'play_next') {
        ref.read(playerProvider.notifier).playNextInQueue(song);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下一首播放: ${song.title}'),
            duration: const Duration(seconds: 1),
          ),
        );
      } else if (value == 'add_queue') {
        ref.read(playerProvider.notifier).addToQueue(song);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已添加到队列: ${song.title}'),
            duration: const Duration(seconds: 1),
          ),
        );
      } else if (value == 'info') {
        _showSongInfoDialog(context, ref, song);
      } else if (value == 'edit') {
        _showEditDialog(context, ref, song);
      } else if (value == 'import_lyrics') {
        _showImportLyricsDialog(context, ref, song);
      } else if (value == 'edit_cover') {
        _showEditCoverDialog(context, ref, song);
      } else if (value == 'tags') {
        SongTagSheet.show(context, song.filePath, song.title);
      } else if (value == 'export') {
        if (context.mounted) {
          ExportDialog.show(context, song);
        }
      } else if (value == 'delete') {
        _showDeleteConfirmDialog(context, ref, song);
      }
    });
  }

  /// 删除歌曲二次确认对话框
  void _showDeleteConfirmDialog(
    BuildContext context,
    WidgetRef ref,
    Song song,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
            SizedBox(width: 8),
            Text(
              '删除歌曲',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '确定要从本地硬盘中永久删除歌曲《${song.title}》吗？',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                song.filePath,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ 此操作将永久删除磁盘上的音频源文件，且无法恢复。',
              style: TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref.read(libraryProvider.notifier).deleteSong(song);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已从硬盘删除歌曲: ${song.title}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('删除失败: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
  }

  /// 查看音乐详细信息对话框
  void _showSongInfoDialog(BuildContext context, WidgetRef ref, Song song) {
    showDialog(
      context: context,
      builder: (ctx) => _SongInfoDialog(song: song),
    );
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
                      unselectedLabelColor: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                      indicatorColor: theme.colorScheme.primary,
                      dividerColor: Colors.transparent,
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      tabs: const [
                        Tab(text: '网易云在线'),
                        Tab(text: '手动输入'),
                      ],
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
                                          textController.text = buffer
                                              .toString();
                                          if (context.mounted) {
                                            DefaultTabController.of(
                                              context,
                                            ).animateTo(1);
                                          }
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
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
                                      icon: const Icon(
                                        Icons.download,
                                        size: 16,
                                      ),
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
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
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
                      fillColor: theme.colorScheme.onSurface.withValues(
                        alpha: 0.06,
                      ),
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
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isLoading
                          ? null
                          : () async {
                              final result = await FilePicker.platform
                                  .pickFiles(type: FileType.image);
                              if (result != null &&
                                  result.files.single.path != null) {
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
                onPressed: isLoading
                    ? null
                    : () async {
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
    // Android 上先请求存储权限
    if (Platform.isAndroid) {
      await _requestStoragePermission();
      // 给用户时间去设置页面授权后返回
      await Future.delayed(const Duration(milliseconds: 500));
    }

    String? dirPath;

    if (Platform.isAndroid) {
      // Android 上使用原生方式获取真实目录路径
      const channel = MethodChannel('com.jmusic.app/permissions');
      try {
        dirPath = await channel.invokeMethod<String>('pickDirectory');
      } catch (e) {
        // fallback 到 file_picker
        dirPath = await FilePicker.platform.getDirectoryPath();
      }
    } else {
      dirPath = await FilePicker.platform.getDirectoryPath();
    }

    if (dirPath == null || dirPath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未选择目录或路径为空')),
        );
      }
      return;
    }

    // 显示选择的路径（调试用）
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描目录: $dirPath')),
      );
    }

    // 如果已有歌曲，弹窗询问覆盖还是累加
    final libraryState = ref.read(libraryProvider);
    if (libraryState.songs.isNotEmpty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Text(
              '添加音乐目录',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
            content: Text(
              '当前已有 ${libraryState.songs.length} 首歌曲，请选择导入方式：',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text(
                  '取消',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop('replace'),
                child: const Text('覆盖'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop('append'),
                child: const Text('累加'),
              ),
            ],
          );
        },
      );

      if (choice == null) return;

      try {
        if (choice == 'replace') {
          await ref.read(libraryProvider.notifier).scanDirectoryReplace(dirPath);
        } else {
          await ref.read(libraryProvider.notifier).scanDirectory(dirPath);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('扫描失败: $e')),
          );
        }
        return;
      }
    } else {
      // 没有歌曲时直接扫描
      try {
        await ref.read(libraryProvider.notifier).scanDirectory(dirPath);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('扫描失败: $e')),
          );
        }
        return;
      }
    }

    final songs = ref.read(libraryProvider).songs;
    final error = ref.read(libraryProvider).error;
    ref.read(playerProvider.notifier).setPlaylist(songs);

    if (mounted) {
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('错误: $error')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描完成，共 ${songs.length} 首歌曲')),
        );
      }
    }
  }

  /// 请求 Android 存储权限
  Future<void> _requestStoragePermission() async {
    const channel = MethodChannel('com.jmusic.app/permissions');
    try {
      final hasPermission =
          await channel.invokeMethod<bool>('hasStoragePermission') ?? false;
      if (!hasPermission) {
        await channel.invokeMethod('requestStoragePermission');
        // 等待用户从设置页面返回
        await Future.delayed(const Duration(seconds: 1));
      }
    } catch (_) {}
  }

  /// 格式化时长
  static String _formatDuration(double seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds.toInt() % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  /// macOS 端设置对话框：目前仅包含「在菜单栏显示歌词」开关。
  /// 该对话框只会在 macOS 上被打开（入口按钮通过 `Platform.isMacOS` 门控）。
  void _showMacosSettingsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('设置'),
          contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          content: SizedBox(
            width: 360,
            child: Consumer(
              builder: (context, ref, _) {
                final enabled = ref.watch(
                  macosStatusBarControllerProvider.select((s) => s.enabled),
                );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: const Text('在菜单栏显示歌词'),
                      subtitle: const Text(
                        '在 macOS 系统菜单栏实时显示当前播放的歌词',
                      ),
                      value: enabled,
                      onChanged: (v) {
                        ref
                            .read(macosStatusBarControllerProvider.notifier)
                            .setEnabled(v);
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('完成'),
            ),
          ],
        );
      },
    );
  }
}

/// 详细信息字段（标签 + 值）
class _InfoEntry {
  final String label;
  final String value;
  final bool monospace;

  const _InfoEntry(
    this.label,
    this.value, {
    this.monospace = false,
  });
}

/// 音乐详细信息弹窗
///
/// 尽量从 Song 模型 + 文件系统 + 嵌入标签中提取所有可读信息：
/// - 基础：标题 / 歌手 / 专辑
/// - 文件：路径、目录、文件名、扩展名、字节大小、修改时间
/// - 音频：时长、格式、估算码率
/// - 在线：QQ songmid / albummid（如果已匹配）
/// - 嵌入：封面尺寸 / 是否有内嵌歌词及字符数
class _SongInfoDialog extends StatefulWidget {
  final Song song;

  const _SongInfoDialog({required this.song});

  @override
  State<_SongInfoDialog> createState() => _SongInfoDialogState();
}

class _SongInfoDialogState extends State<_SongInfoDialog> {
  Uint8List? _coverBytes;
  bool _coverLoading = true;
  int? _coverByteCount;

  bool _embeddedLyricsLoading = true;
  String? _embeddedLyrics;

  @override
  void initState() {
    super.initState();
    _loadEmbeddedAssets();
  }

  Future<void> _loadEmbeddedAssets() async {
    // 嵌入封面
    try {
      final cover = await rust_scanner.readEmbeddedCover(
        filePath: widget.song.filePath,
      );
      if (mounted) {
        setState(() {
          _coverBytes = cover;
          _coverByteCount = cover?.length;
          _coverLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _coverLoading = false);
    }

    // 嵌入歌词
    try {
      final lrc = await rust_scanner.readEmbeddedLyrics(
        filePath: widget.song.filePath,
      );
      if (mounted) {
        setState(() {
          _embeddedLyrics = lrc;
          _embeddedLyricsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _embeddedLyricsLoading = false);
    }
  }

  // —— 工具函数 ——

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _humanDuration(double seconds) {
    if (seconds <= 0) return '-';
    final total = seconds.toInt();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final ms = ((seconds - total) * 1000).toInt();
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}'
          '.${ms.toString().padLeft(3, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}'
        '.${ms.toString().padLeft(3, '0')}';
  }

  String _humanTimestamp(BigInt secondsSinceEpoch) {
    if (secondsSinceEpoch == BigInt.zero) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(
      (secondsSinceEpoch * BigInt.from(1000)).toInt(),
      isUtc: false,
    );
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} '
        '${pad(dt.hour)}:${pad(dt.minute)}:${pad(dt.second)}';
  }

  String _estimatedBitrate(BigInt fileSize, double duration) {
    if (duration <= 0) return '-';
    final bits = fileSize.toInt() * 8;
    final kbps = bits / duration / 1000;
    return '${kbps.toStringAsFixed(0)} kbps（估算）';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = widget.song;

    final filePath = song.filePath;
    final separator = filePath.contains('\\') ? '\\' : '/';
    final lastSep = filePath.lastIndexOf(separator);
    final fileName = lastSep >= 0 ? filePath.substring(lastSep + 1) : filePath;
    final dirPath = lastSep >= 0 ? filePath.substring(0, lastSep) : '-';
    final dotIdx = fileName.lastIndexOf('.');
    final baseName = dotIdx > 0 ? fileName.substring(0, dotIdx) : fileName;

    final entries = <_InfoEntry>[
      _InfoEntry('标题', song.title.isEmpty ? '-' : song.title),
      _InfoEntry('歌手', song.artist.isEmpty ? '-' : song.artist),
      _InfoEntry('专辑', song.album.isEmpty ? '-' : song.album),
      _InfoEntry('时长', _humanDuration(song.duration)),
      _InfoEntry('格式', song.format.toUpperCase()),
      _InfoEntry(
        '文件大小',
        '${_humanSize(song.fileSize.toInt())}'
            '（${song.fileSize} B）',
      ),
      _InfoEntry('估算码率', _estimatedBitrate(song.fileSize, song.duration)),
      _InfoEntry('文件名', fileName, monospace: true),
      _InfoEntry('基础名', baseName, monospace: true),
      _InfoEntry('所在目录', dirPath, monospace: true),
      _InfoEntry('完整路径', filePath, monospace: true),
      _InfoEntry('修改时间', _humanTimestamp(song.modifiedAt)),
      _InfoEntry(
        '修改时间戳',
        '${song.modifiedAt} (Unix 秒)',
        monospace: true,
      ),
      _InfoEntry(
        'QQ songmid',
        (song.songmid == null || song.songmid!.isEmpty)
            ? '-（未匹配）'
            : song.songmid!,
        monospace: true,
      ),
      _InfoEntry(
        'QQ albummid',
        (song.albummid == null || song.albummid!.isEmpty)
            ? '-（未匹配）'
            : song.albummid!,
        monospace: true,
      ),
      _InfoEntry(
        '内嵌封面',
        _coverLoading
            ? '正在读取...'
            : (_coverByteCount == null
                ? '无'
                : '有，${_humanSize(_coverByteCount!)}'),
      ),
      _InfoEntry(
        '内嵌歌词',
        _embeddedLyricsLoading
            ? '正在读取...'
            : (_embeddedLyrics == null || _embeddedLyrics!.isEmpty
                ? '无'
                : '有，${_embeddedLyrics!.length} 字符'),
      ),
    ];

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '音乐信息',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 15,
              ),
            ),
          ),
          IconButton(
            tooltip: '复制全部信息',
            onPressed: () {
              final buf = StringBuffer();
              for (final e in entries) {
                buf.writeln('${e.label}: ${e.value}');
              }
              Clipboard.setData(ClipboardData(text: buf.toString()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制到剪贴板')),
              );
            },
            icon: Icon(
              Icons.copy_all_outlined,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部封面 + 主信息
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCoverThumb(theme),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          song.title.isEmpty ? '-' : song.title,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          song.artist.isEmpty ? '-' : song.artist,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.75),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          song.album.isEmpty ? '-' : song.album,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _chip(
                              theme,
                              song.format.toUpperCase(),
                            ),
                            _chip(
                              theme,
                              _humanDuration(song.duration),
                            ),
                            _chip(
                              theme,
                              _humanSize(song.fileSize.toInt()),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
              ),
              const SizedBox(height: 4),
              // 详细字段表
              ...entries.map((e) => _buildEntryRow(theme, e)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '关闭',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoverThumb(ThemeData theme) {
    Widget child;
    if (_coverLoading) {
      child = SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.primary,
        ),
      );
    } else if (_coverBytes != null) {
      child = Image.memory(_coverBytes!, fit: BoxFit.cover);
    } else {
      child = Icon(
        Icons.music_note,
        size: 32,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
      );
    }
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _chip(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildEntryRow(ThemeData theme, _InfoEntry e) {
    final labelColor = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final valueColor = theme.colorScheme.onSurface.withValues(alpha: 0.95);
    final valueStyle = TextStyle(
      color: valueColor,
      fontSize: 12.5,
      fontFamily: e.monospace ? 'monospace' : null,
      height: 1.4,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              e.label,
              style: TextStyle(color: labelColor, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(e.value, style: valueStyle),
          ),
          IconButton(
            tooltip: '复制',
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: e.value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已复制：${e.label}'),
                  duration: const Duration(milliseconds: 800),
                ),
              );
            },
            icon: Icon(
              Icons.copy_outlined,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// 歌曲列表项（支持鼠标悬停动效、自适应宽窄屏与快捷操作）
class _SongListTile extends StatefulWidget {
  final int index;
  final Song song;
  final bool isWide;
  final bool isCurrentSong;
  final bool isPlaying;
  final Color dimColor;
  final VoidCallback onTap;
  final void Function(TapUpDetails details) onSecondaryTapUp;
  final void Function(LongPressStartDetails details) onLongPressStart;
  final void Function(String artist) onArtistTap;
  final void Function(String album) onAlbumTap;
  final VoidCallback onPlayNext;
  final VoidCallback onAddToQueue;
  final void Function(Offset position) onMoreTap;

  const _SongListTile({
    super.key,
    required this.index,
    required this.song,
    required this.isWide,
    required this.isCurrentSong,
    required this.isPlaying,
    required this.dimColor,
    required this.onTap,
    required this.onSecondaryTapUp,
    required this.onLongPressStart,
    required this.onArtistTap,
    required this.onAlbumTap,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onMoreTap,
  });

  @override
  State<_SongListTile> createState() => _SongListTileState();
}

class _SongListTileState extends State<_SongListTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = widget.song;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onSecondaryTapUp: widget.onSecondaryTapUp,
        onLongPressStart: widget.onLongPressStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: widget.isCurrentSong
                      ? theme.colorScheme.primary.withValues(
                          alpha: _isHovered ? 0.18 : 0.12,
                        )
                      : (_isHovered
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.transparent),
                  border: widget.isCurrentSong
                      ? Border.all(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.30,
                          ),
                          width: 0.8,
                        )
                      : (_isHovered
                          ? Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 0.8,
                            )
                          : null),
                ),
                child: widget.isWide
                    ? _buildWideRow(theme, song)
                    : _buildNarrowRow(theme, song),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 宽屏模式行内容（≥ 720px）
  Widget _buildWideRow(ThemeData theme, Song song) {
    final formatUpper = song.format.toUpperCase();
    final isLossless =
        formatUpper == 'FLAC' || formatUpper == 'WAV' || formatUpper == 'APE';

    return Row(
      children: [
        // 序号 / 动态播放音波指示器
        SizedBox(
          width: 42,
          child: widget.isCurrentSong
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: PlayingWaveIndicator(
                    color: theme.colorScheme.primary,
                    isPlaying: widget.isPlaying,
                    height: 14,
                    width: 16,
                  ),
                )
              : Text(
                  (widget.index + 1).toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
        ),

        // 标题（单行垂直居中）
        Expanded(
          flex: 4,
          child: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: widget.isCurrentSong
                  ? theme.colorScheme.primary
                  : Colors.white.withValues(alpha: 0.92),
              fontWeight: widget.isCurrentSong
                  ? FontWeight.w700
                  : FontWeight.w600,
              fontSize: 13.5,
              letterSpacing: -0.1,
            ),
          ),
        ),
        const SizedBox(width: 12),

        // 歌手（独立列，移除刺眼虚线下划线，采用清爽光泽悬停）
        Expanded(
          flex: 2,
          child: song.artist.isNotEmpty
              ? MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onArtistTap(song.artist),
                    child: Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(
                          alpha: _isHovered ? 0.75 : 0.55,
                        ),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
              : Text(
                  '-',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.dimColor,
                    fontSize: 12,
                  ),
                ),
        ),
        const SizedBox(width: 12),

        // 专辑（独立列）
        Expanded(
          flex: 2,
          child: song.album.isNotEmpty
              ? MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onAlbumTap(song.album),
                    child: Text(
                      song.album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(
                          alpha: _isHovered ? 0.68 : 0.45,
                        ),
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                )
              : Text(
                  '-',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.dimColor,
                    fontSize: 12,
                  ),
                ),
        ),
        const SizedBox(width: 12),

        // 文件大小（等宽字体）
        SizedBox(
          width: 74,
          child: Text(
            _HomePageState._formatSongFileSize(song.fileSize),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 11.5,
              fontFamily: 'monospace',
            ),
          ),
        ),

        // 规格胶囊徽章（无损采用琥珀金，与播放页统一）
        SizedBox(
          width: 64,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isLossless
                    ? Colors.amber.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: isLossless
                      ? Colors.amber.withValues(alpha: 0.40)
                      : Colors.white.withValues(alpha: 0.12),
                  width: 0.6,
                ),
              ),
              child: Text(
                formatUpper,
                style: TextStyle(
                  color: isLossless
                      ? Colors.amberAccent
                      : Colors.white.withValues(alpha: 0.6),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),

        // 时长（等宽字体）
        SizedBox(
          width: 54,
          child: Text(
            _HomePageState._formatDuration(song.duration),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.48),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.right,
          ),
        ),

        // 悬浮快捷操作栏（占位 80px）
        SizedBox(
          width: 80,
          child: AnimatedOpacity(
            opacity: _isHovered ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: _isHovered
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.playlist_play_rounded),
                        iconSize: 18,
                        tooltip: '下一首播放',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        color: Colors.white70,
                        hoverColor:
                            theme.colorScheme.primary.withValues(alpha: 0.2),
                        onPressed: widget.onPlayNext,
                      ),
                      const SizedBox(width: 2),
                      IconButton(
                        icon: const Icon(Icons.playlist_add_rounded),
                        iconSize: 18,
                        tooltip: '添加到队列',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        color: Colors.white70,
                        hoverColor:
                            theme.colorScheme.primary.withValues(alpha: 0.2),
                        onPressed: widget.onAddToQueue,
                      ),
                      const SizedBox(width: 2),
                      Builder(
                        builder: (btnContext) {
                          return IconButton(
                            icon: const Icon(Icons.more_horiz_rounded),
                            iconSize: 18,
                            tooltip: '更多选项',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              minHeight: 26,
                            ),
                            color: Colors.white70,
                            hoverColor: theme.colorScheme.primary
                                .withValues(alpha: 0.2),
                            onPressed: () {
                              final box = btnContext
                                  .findRenderObject() as RenderBox?;
                              final position = box != null
                                  ? box.localToGlobal(
                                      box.size.bottomRight(Offset.zero))
                                  : Offset.zero;
                              widget.onMoreTap(position);
                            },
                          );
                        },
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  /// 窄屏模式行内容（< 720px）
  Widget _buildNarrowRow(ThemeData theme, Song song) {
    final formatUpper = song.format.toUpperCase();
    final isLossless =
        formatUpper == 'FLAC' || formatUpper == 'WAV' || formatUpper == 'APE';

    return Row(
      children: [
        // 序号 / 动态播放音波指示器
        SizedBox(
          width: 36,
          child: widget.isCurrentSong
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: PlayingWaveIndicator(
                    color: theme.colorScheme.primary,
                    isPlaying: widget.isPlaying,
                    height: 14,
                    width: 16,
                  ),
                )
              : Text(
                  (widget.index + 1).toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
        ),

        // 标题 + 歌手
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.isCurrentSong
                      ? theme.colorScheme.primary
                      : Colors.white.withValues(alpha: 0.92),
                  fontWeight: widget.isCurrentSong
                      ? FontWeight.w700
                      : FontWeight.w600,
                  fontSize: 13.5,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.50),
                  fontSize: 11.5,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),

        // 专辑（点击搜索此专辑）
        Expanded(
          flex: 3,
          child: song.album.isNotEmpty
              ? MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onAlbumTap(song.album),
                    child: Text(
                      song.album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(
                          alpha: _isHovered ? 0.68 : 0.45,
                        ),
                        fontSize: 12,
                      ),
                    ),
                  ),
                )
              : Text(
                  '-',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.dimColor,
                    fontSize: 12,
                  ),
                ),
        ),

        // 规格徽章
        SizedBox(
          width: 52,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: isLossless
                    ? Colors.amber.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: isLossless
                      ? Colors.amber.withValues(alpha: 0.40)
                      : Colors.white.withValues(alpha: 0.12),
                  width: 0.6,
                ),
              ),
              child: Text(
                formatUpper,
                style: TextStyle(
                  color: isLossless
                      ? Colors.amberAccent
                      : Colors.white.withValues(alpha: 0.6),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),

        // 时长
        SizedBox(
          width: 48,
          child: Text(
            _HomePageState._formatDuration(song.duration),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.48),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

