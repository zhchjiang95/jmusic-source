import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/pages/player_page.dart';

/// 底部迷你播放栏
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只监听歌曲信息和播放状态，不监听 position 等高频变化字段
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final theme = Theme.of(context);

    if (currentSong == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const PlayerPage(),
            transitionsBuilder: (_, animation, __, child) {
              return SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(0, 1),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条（独立 Consumer 避免重建整个组件）
            Consumer(
              builder: (context, ref, _) {
                final position = ref.watch(
                  playerProvider.select((s) => s.position),
                );
                final duration = ref.watch(
                  playerProvider.select((s) => s.duration),
                );
                final progress = duration.inMilliseconds > 0
                    ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                        0.0,
                        1.0,
                      )
                    : 0.0;
                return LinearProgressIndicator(
                  value: progress,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
                );
              },
            ),
            // 内容
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  // 封面（独立 Consumer，只在 coverData 变化时重建）
                  Hero(
                    tag: 'album_art',
                    child: Consumer(
                      builder: (context, ref, _) {
                        final coverData = ref.watch(
                          playerProvider.select((s) => s.coverData),
                        );
                        return Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.primary.withValues(
                                  alpha: 0.5,
                                ),
                                theme.colorScheme.tertiary.withValues(
                                  alpha: 0.5,
                                ),
                              ],
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: coverData != null
                                ? Image.memory(
                                    Uint8List.fromList(coverData),
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.music_note,
                                      color: Colors.white54,
                                      size: 22,
                                    ),
                                  )
                                : const Icon(
                                    Icons.music_note,
                                    color: Colors.white54,
                                    size: 22,
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 歌曲信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currentSong.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          currentSong.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 播放/暂停按钮
                  IconButton(
                    onPressed: () =>
                        ref.read(playerProvider.notifier).togglePlayPause(),
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  // 下一首按钮
                  IconButton(
                    onPressed: () => ref.read(playerProvider.notifier).next(),
                    icon: const Icon(
                      Icons.skip_next_rounded,
                      color: Colors.white70,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
