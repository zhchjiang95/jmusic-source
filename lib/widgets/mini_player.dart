import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/providers/cast_provider.dart';
import 'package:jmusic/pages/player_page.dart';
import 'package:jmusic/widgets/cast_sheet.dart';

/// 底部悬浮声学迷你播放舱（与先锋双栏播放页统一视觉语言）
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 仅监听歌曲信息与播放状态，进度条由局部 Consumer 独立刷新
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final theme = Theme.of(context);

    if (currentSong == null) return const SizedBox.shrink();

    final formatUpper = currentSong.format.toUpperCase();
    final isLossless =
        formatUpper == 'FLAC' || formatUpper == 'WAV' || formatUpper == 'APE';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, _, _) => const PlayerPage(),
            transitionsBuilder: (_, animation, _, child) {
              return SlideTransition(
                position: Tween<Offset>(
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, 10),
              spreadRadius: -2,
            ),
            if (isPlaying)
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF10101A).withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                  width: 0.8,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 顶部流光进度细线（独立 Consumer 避免重建整个组件）
                  Consumer(
                    builder: (context, ref, _) {
                      final position = ref.watch(
                        playerProvider.select((s) => s.position),
                      );
                      final duration = ref.watch(
                        playerProvider.select((s) => s.duration),
                      );
                      final progress = duration.inMilliseconds > 0
                          ? (position.inMilliseconds / duration.inMilliseconds)
                              .clamp(0.0, 1.0)
                          : 0.0;
                      return LinearProgressIndicator(
                        value: progress,
                        minHeight: 2.2,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        valueColor: AlwaysStoppedAnimation(
                          theme.colorScheme.primary,
                        ),
                      );
                    },
                  ),
                  // 主体内容区
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 560;
                        return Row(
                          children: [
                            // 专辑封面（独立 Consumer，仅在 coverData 变化时重建）
                            Hero(
                              tag: 'album_art',
                              child: Consumer(
                                builder: (context, ref, _) {
                                  final coverData = ref.watch(
                                    playerProvider.select((s) => s.coverData),
                                  );
                                  return Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: theme.colorScheme.primary
                                              .withValues(
                                                alpha: isPlaying ? 0.32 : 0.12,
                                              ),
                                          blurRadius: 12,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
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
                                      borderRadius: BorderRadius.circular(12),
                                      child: coverData != null
                                          ? Image.memory(
                                              Uint8List.fromList(coverData),
                                              fit: BoxFit.cover,
                                              gaplessPlayback: true,
                                              errorBuilder: (_, _, _) =>
                                                  const Icon(
                                                    Icons.album_rounded,
                                                    color: Colors.white54,
                                                    size: 22,
                                                  ),
                                            )
                                          : const Icon(
                                              Icons.album_rounded,
                                              color: Colors.white54,
                                              size: 22,
                                            ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 14),
                            // 歌曲标题 + 规格徽章 + 歌手信息
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          currentSong.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                      if (formatUpper.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isLossless
                                                ? Colors.amber.withValues(
                                                    alpha: 0.15,
                                                  )
                                                : Colors.white.withValues(
                                                    alpha: 0.07,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              5,
                                            ),
                                            border: Border.all(
                                              color: isLossless
                                                  ? Colors.amber.withValues(
                                                      alpha: 0.4,
                                                    )
                                                  : Colors.white.withValues(
                                                      alpha: 0.12,
                                                    ),
                                              width: 0.6,
                                            ),
                                          ),
                                          child: Text(
                                            isLossless
                                                ? 'HI-RES · $formatUpper'
                                                : formatUpper,
                                            style: TextStyle(
                                              color: isLossless
                                                  ? Colors.amberAccent
                                                  : Colors.white60,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    currentSong.album.isNotEmpty
                                        ? '${currentSong.artist} · ${currentSong.album}'
                                        : currentSong.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.55,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 宽屏显示实时时间刻度
                            if (isWide) ...[
                              Consumer(
                                builder: (context, ref, _) {
                                  final position = ref.watch(
                                    playerProvider.select((s) => s.position),
                                  );
                                  final duration = ref.watch(
                                    playerProvider.select((s) => s.duration),
                                  );
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.05,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${_formatDuration(position)} / ${_formatDuration(duration)}',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 12),
                            ],
                            // 上一首按钮
                            IconButton(
                              onPressed: () =>
                                  ref.read(playerProvider.notifier).previous(),
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.skip_previous_rounded,
                                color: Colors.white70,
                                size: 24,
                              ),
                              tooltip: '上一首',
                            ),
                            const SizedBox(width: 4),
                            // 播放/暂停主发光圆钮（与播放页控制舱风格统一）
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.primary,
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.42,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                onPressed: () => ref
                                    .read(playerProvider.notifier)
                                    .togglePlayPause(),
                                icon: Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                tooltip: isPlaying ? '暂停' : '播放',
                              ),
                            ),
                            const SizedBox(width: 4),
                            // 下一首按钮
                            IconButton(
                              onPressed: () =>
                                  ref.read(playerProvider.notifier).next(),
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.skip_next_rounded,
                                color: Colors.white70,
                                size: 24,
                              ),
                              tooltip: '下一首',
                            ),
                            const SizedBox(width: 6),
                            // DLNA 投放按钮
                            Consumer(
                              builder: (context, ref, _) {
                                final isCasting = ref.watch(
                                  castProvider.select((s) => s.isCasting),
                                );
                                return IconButton(
                                  onPressed: () => showCastSheet(context),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'DLNA 投放',
                                  icon: Icon(
                                    isCasting
                                        ? Icons.cast_connected_rounded
                                        : Icons.cast_rounded,
                                    color: isCasting
                                        ? theme.colorScheme.primary
                                        : Colors.white54,
                                    size: 19,
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
