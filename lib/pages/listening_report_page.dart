import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:jmusic/src/rust/api/play_stats.dart' as rust_play_stats;
import 'package:jmusic/src/rust/api/play_stats.dart' show PlayCountEntry;

/// 听歌报告页面 — Spotify Wrapped 风格，支持导出图片
class ListeningReportPage extends StatefulWidget {
  const ListeningReportPage({super.key});

  @override
  State<ListeningReportPage> createState() => _ListeningReportPageState();
}

class _ListeningReportPageState extends State<ListeningReportPage> {
  final PageController _pageController = PageController();
  final List<GlobalKey> _cardKeys = List.generate(5, (_) => GlobalKey());
  int _currentPage = 0;
  bool _isSaving = false;

  late final _ReportData _data;

  @override
  void initState() {
    super.initState();
    _data = _buildReportData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  _ReportData _buildReportData() {
    final stats = rust_play_stats.getPlayStats();
    final totalPlays = stats.fold<int>(0, (sum, e) => sum + e.count);
    final totalSongs = stats.length;

    // Top 5 songs
    final topSongs = stats.take(5).toList();

    // Top artists (aggregate by artist)
    final artistMap = <String, int>{};
    for (final e in stats) {
      final artist = e.artist.isNotEmpty ? e.artist : '未知歌手';
      artistMap[artist] = (artistMap[artist] ?? 0) + e.count;
    }
    final topArtists = artistMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topArtistsList = topArtists.take(5).toList();
    final uniqueArtists = artistMap.length;

    return _ReportData(
      totalPlays: totalPlays,
      totalSongs: totalSongs,
      uniqueArtists: uniqueArtists,
      topSongs: topSongs,
      topArtists: topArtistsList,
    );
  }

  Future<void> _saveCurrentCard() async {
    setState(() => _isSaving = true);
    try {
      final key = _cardKeys[_currentPage];
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'jmusic_report_${_currentPage + 1}_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(pngBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存: ${file.path}'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: '打开目录',
              onPressed: () => _openDirectory(dir.path),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
    setState(() => _isSaving = false);
  }

  Future<void> _saveAllCards() async {
    setState(() => _isSaving = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      int saved = 0;

      for (int i = 0; i < _cardKeys.length; i++) {
        final key = _cardKeys[i];
        if (key.currentContext == null) continue;
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        final pngBytes = byteData!.buffer.asUint8List();
        final file = File('${dir.path}/jmusic_report_${i + 1}_$ts.png');
        await file.writeAsBytes(pngBytes);
        saved++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存 $saved 张报告图片'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: '打开目录',
              onPressed: () => _openDirectory(dir.path),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
    setState(() => _isSaving = false);
  }

  void _openDirectory(String path) {
    if (Platform.isWindows) {
      Process.run('explorer', [path]);
    } else if (Platform.isMacOS) {
      Process.run('open', [path]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [path]);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data.totalPlays == 0) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F1A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('听歌报告', style: TextStyle(fontSize: 16)),
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.music_off, size: 64, color: Colors.white24),
              SizedBox(height: 16),
              Text('暂无播放记录', style: TextStyle(color: Colors.white38)),
              SizedBox(height: 8),
              Text('多听几首歌再来看报告吧~',
                  style: TextStyle(color: Colors.white24, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('听歌报告', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : _saveCurrentCard,
            icon: const Icon(Icons.save_alt, size: 20),
            tooltip: '保存当前页',
          ),
          IconButton(
            onPressed: _isSaving ? null : _saveAllCards,
            icon: const Icon(Icons.photo_library_outlined, size: 20),
            tooltip: '保存全部页',
          ),
        ],
      ),
      body: Column(
        children: [
          // 页面指示器（可点击切换）
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                return GestureDetector(
                  onTap: () {
                    _pageController.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _currentPage ? 24 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      color: i == _currentPage
                          ? _getPageColor(i)
                          : Colors.white24,
                    ),
                  ),
                );
              }),
            ),
          ),
          // 卡片翻页
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                },
              ),
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _buildPage0Overview(),
                  _buildPage1TopSong(),
                  _buildPage2TopSongs(),
                  _buildPage3TopArtists(),
                  _buildPage4Summary(),
                ],
              ),
            ),
          ),
          // 底部提示
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              '← 左右滑动翻页 →',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getPageColor(int page) {
    const colors = [
      Color(0xFF1DB954), // Spotify green
      Color(0xFFFF6B6B), // coral
      Color(0xFF845EF7), // purple
      Color(0xFF339AF0), // blue
      Color(0xFFFCC419), // gold
    ];
    return colors[page % colors.length];
  }

  /// Page 0: 总览数据
  Widget _buildPage0Overview() {
    return Center(
      child: RepaintBoundary(
        key: _cardKeys[0],
        child: _WrappedCard(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1DB954), Color(0xFF0D7A3A)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '🎵',
                style: TextStyle(fontSize: 48),
              ),
              const SizedBox(height: 16),
              const Text(
                '你的听歌报告',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '${_data.totalPlays}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '次播放',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatBubble(
                    value: '${_data.totalSongs}',
                    label: '首歌曲',
                  ),
                  _StatBubble(
                    value: '${_data.uniqueArtists}',
                    label: '位歌手',
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _brandWatermark(),
            ],
          ),
        ),
      ),
    );
  }

  /// Page 1: 最爱的歌
  Widget _buildPage1TopSong() {
    final top = _data.topSongs.isNotEmpty ? _data.topSongs.first : null;
    if (top == null) return const SizedBox.shrink();

    return Center(
      child: RepaintBoundary(
        key: _cardKeys[1],
        child: _WrappedCard(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF6B6B), Color(0xFFCC3333)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '你最爱的歌',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              // 大号音符图标
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                top.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                top.artist,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                child: Text(
                  '播放了 ${top.count} 次',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              _brandWatermark(),
            ],
          ),
        ),
      ),
    );
  }

  /// Page 2: Top 5 歌曲排行
  Widget _buildPage2TopSongs() {
    return Center(
      child: RepaintBoundary(
        key: _cardKeys[2],
        child: _WrappedCard(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF845EF7), Color(0xFF5F3DC4)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '最常播放 TOP 5',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              ...List.generate(
                min(5, _data.topSongs.length),
                (i) {
                  final song = _data.topSongs[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        // 排名
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: i == 0
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.6),
                              fontSize: i == 0 ? 20 : 16,
                              fontWeight: FontWeight.w800,
                            ),
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
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: i == 0 ? 16 : 14,
                                  fontWeight: i == 0
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                song.artist,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // 播放次数
                        Text(
                          '${song.count}次',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              _brandWatermark(),
            ],
          ),
        ),
      ),
    );
  }

  /// Page 3: Top 歌手
  Widget _buildPage3TopArtists() {
    return Center(
      child: RepaintBoundary(
        key: _cardKeys[3],
        child: _WrappedCard(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF339AF0), Color(0xFF1864AB)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '最爱的歌手',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              ...List.generate(
                min(5, _data.topArtists.length),
                (i) {
                  final artist = _data.topArtists[i];
                  final barWidth = _data.topArtists.isNotEmpty
                      ? (artist.value / _data.topArtists.first.value)
                      : 0.0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                artist.key,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: i == 0 ? 16 : 14,
                                  fontWeight: i == 0
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${artist.value}次',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // 进度条
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: barWidth,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.1),
                            valueColor: AlwaysStoppedAnimation(
                              Colors.white.withValues(alpha: i == 0 ? 0.9 : 0.5),
                            ),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              _brandWatermark(),
            ],
          ),
        ),
      ),
    );
  }

  /// Page 4: 总结
  Widget _buildPage4Summary() {
    final avgPerSong = _data.totalSongs > 0
        ? (_data.totalPlays / _data.totalSongs).toStringAsFixed(1)
        : '0';
    final topArtist =
        _data.topArtists.isNotEmpty ? _data.topArtists.first.key : '—';

    return Center(
      child: RepaintBoundary(
        key: _cardKeys[4],
        child: _WrappedCard(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFCC419), Color(0xFFE67700)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '✨',
                style: TextStyle(fontSize: 40),
              ),
              const SizedBox(height: 12),
              const Text(
                '你的音乐品味',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 28),
              _SummaryItem(
                icon: Icons.library_music,
                text: '共收听了 ${_data.totalSongs} 首不同的歌',
              ),
              const SizedBox(height: 14),
              _SummaryItem(
                icon: Icons.repeat,
                text: '平均每首歌听了 $avgPerSong 次',
              ),
              const SizedBox(height: 14),
              _SummaryItem(
                icon: Icons.person,
                text: '最爱的歌手是 $topArtist',
              ),
              const SizedBox(height: 14),
              _SummaryItem(
                icon: Icons.people,
                text: '探索了 ${_data.uniqueArtists} 位不同的歌手',
              ),
              const SizedBox(height: 32),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                child: const Text(
                  '继续探索更多好音乐 🎶',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _brandWatermark(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _brandWatermark() {
    return Text(
      'JMusic',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.3),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 2,
      ),
    );
  }
}

/// 报告数据
class _ReportData {
  final int totalPlays;
  final int totalSongs;
  final int uniqueArtists;
  final List<PlayCountEntry> topSongs;
  final List<MapEntry<String, int>> topArtists;

  const _ReportData({
    required this.totalPlays,
    required this.totalSongs,
    required this.uniqueArtists,
    required this.topSongs,
    required this.topArtists,
  });
}

/// Wrapped 风格卡片容器
class _WrappedCard extends StatelessWidget {
  final Gradient gradient;
  final Widget child;

  const _WrappedCard({required this.gradient, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      height: 520,
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: child,
      ),
    );
  }
}

/// 统计气泡
class _StatBubble extends StatelessWidget {
  final String value;
  final String label;

  const _StatBubble({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.15),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// 总结项
class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SummaryItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
