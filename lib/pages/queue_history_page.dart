import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/services/play_history_service.dart';
import 'package:jmusic/src/rust/models/song.dart';

/// 播放队列与最近播放历史页面
class QueueHistoryPage extends ConsumerStatefulWidget {
  const QueueHistoryPage({super.key});

  @override
  ConsumerState<QueueHistoryPage> createState() => _QueueHistoryPageState();
}

class _QueueHistoryPageState extends ConsumerState<QueueHistoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          '队列与历史',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '播放队列'),
            Tab(text: '最近播放'),
          ],
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: Colors.white54,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _QueueTab(),
          _HistoryTab(),
        ],
      ),
    );
  }
}

/// 播放队列 Tab
class _QueueTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final queue = playerState.queue;
    final currentSong = playerState.currentSong;
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        // 正在播放
        if (currentSong != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '正在播放',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SongTile(
                    song: currentSong,
                    isActive: true,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),

        // 队列标题
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Text(
                  '播放队列',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${queue.length} 首',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                if (queue.isNotEmpty)
                  TextButton(
                    onPressed: () =>
                        ref.read(playerProvider.notifier).clearQueue(),
                    child: Text(
                      '清空',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // 队列列表
        if (queue.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(Icons.queue_music_rounded,
                      color: Colors.white.withValues(alpha: 0.15), size: 48),
                  const SizedBox(height: 12),
                  Text(
                    '队列为空',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '右键歌曲选择"下一首播放"或"添加到队列"',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.2),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = queue[index];
                return Dismissible(
                  key: ValueKey('queue_${index}_${song.filePath}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.red.withValues(alpha: 0.2),
                    child: const Icon(Icons.delete_outline,
                        color: Colors.redAccent, size: 20),
                  ),
                  onDismissed: (_) {
                    ref.read(playerProvider.notifier).removeFromQueue(index);
                  },
                  child: _SongTile(
                    song: song,
                    trailing: Text(
                      '#${index + 1}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 11,
                      ),
                    ),
                    onTap: () {
                      // 移除并播放
                      ref.read(playerProvider.notifier).removeFromQueue(index);
                      ref.read(playerProvider.notifier).playSongAt(
                            ref
                                .read(playerProvider)
                                .playlist
                                .indexWhere((s) => s.filePath == song.filePath),
                          );
                    },
                  ),
                );
              },
              childCount: queue.length,
            ),
          ),
      ],
    );
  }
}

/// 最近播放 Tab
class _HistoryTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  @override
  Widget build(BuildContext context) {
    final history = PlayHistoryService.instance.entries;
    final theme = Theme.of(context);
    // 需要 watch playerProvider 来触发重建（播放新歌后刷新）
    ref.watch(playerProvider.select((s) => s.currentSong));

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded,
                color: Colors.white.withValues(alpha: 0.15), size: 48),
            const SizedBox(height: 12),
            Text(
              '暂无播放历史',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 清除按钮
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text(
                '最近 ${history.length} 首',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  ref.read(playerProvider.notifier).clearPlayHistory();
                  setState(() {});
                },
                child: Text(
                  '清空历史',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 历史列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final entry = history[index];
              return _HistoryTile(
                entry: entry,
                onTap: () {
                  // 在播放列表中找到并播放
                  final playlist = ref.read(playerProvider).playlist;
                  final songIndex = playlist
                      .indexWhere((s) => s.filePath == entry.filePath);
                  if (songIndex != -1) {
                    ref.read(playerProvider.notifier).playSongAt(songIndex);
                  }
                },
                onAddToQueue: () {
                  final playlist = ref.read(playerProvider).playlist;
                  final song = playlist.cast<Song?>().firstWhere(
                        (s) => s?.filePath == entry.filePath,
                        orElse: () => null,
                      );
                  if (song != null) {
                    ref.read(playerProvider.notifier).addToQueue(song);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已添加到队列: ${entry.title}'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 歌曲 Tile 组件
class _SongTile extends StatelessWidget {
  final Song song;
  final bool isActive;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SongTile({
    required this.song,
    this.isActive = false,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // 歌曲图标
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isActive
                      ? theme.colorScheme.primary.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isActive ? Icons.equalizer_rounded : Icons.music_note_rounded,
                  color: isActive
                      ? theme.colorScheme.primary
                      : Colors.white38,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              // 歌曲信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isActive
                            ? theme.colorScheme.primary
                            : Colors.white,
                        fontSize: 13,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// 历史记录 Tile 组件
class _HistoryTile extends StatelessWidget {
  final PlayHistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onAddToQueue;

  const _HistoryTile({
    required this.entry,
    required this.onTap,
    required this.onAddToQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              // 图标
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  color: Colors.white38,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              // 歌曲信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Text(
                          ' · ${entry.relativeTime}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.25),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 添加到队列按钮
              IconButton(
                onPressed: onAddToQueue,
                icon: Icon(
                  Icons.playlist_add_rounded,
                  color: Colors.white.withValues(alpha: 0.4),
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: '添加到队列',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
