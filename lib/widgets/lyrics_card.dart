import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// JMusic 官网地址（用于二维码）
const String kJMusicWebsite = 'https://fiume.cn/jmusic/';

/// 歌词卡片生成与分享组件
///
/// 选中一句歌词后，生成精美卡片（封面模糊背景 + 歌词 + 歌曲信息 + 二维码），
/// 可导出为 PNG 图片保存到本地。
class LyricsCardDialog extends StatefulWidget {
  final String lyricText;
  final String songTitle;
  final String artist;
  final String album;
  final List<int>? coverData;

  const LyricsCardDialog({
    super.key,
    required this.lyricText,
    required this.songTitle,
    required this.artist,
    this.album = '',
    this.coverData,
  });

  @override
  State<LyricsCardDialog> createState() => _LyricsCardDialogState();
}

class _LyricsCardDialogState extends State<LyricsCardDialog> {
  final GlobalKey _cardKey = GlobalKey();
  bool _isSaving = false;
  String? _savedPath;

  Future<void> _saveCard() async {
    setState(() {
      _isSaving = true;
      _savedPath = null;
    });

    try {
      final boundary = _cardKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'lyrics_card_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(pngBytes);

      setState(() {
        _savedPath = file.path;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存到: ${file.path}'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: '打开目录',
              onPressed: () => _openDirectory(dir.path),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
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
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 卡片预览
          RepaintBoundary(
            key: _cardKey,
            child: _buildCard(theme),
          ),
          const SizedBox(height: 16),
          // 操作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white70),
                label:
                    const Text('关闭', style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(width: 24),
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveCard,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_alt),
                label: Text(_savedPath != null ? '已保存' : '保存图片'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCard(ThemeData theme) {
    final hasCover =
        widget.coverData != null && widget.coverData!.isNotEmpty;

    return Container(
      width: 360,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        children: [
          // 背景层：封面模糊 或 渐变
          Positioned.fill(
            child: hasCover
                ? _buildCoverBackground()
                : _buildGradientBackground(theme),
          ),
          // 暗色遮罩
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ),
          // 内容 — 使用 IntrinsicHeight 让内容自适应高度并居中
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 小封面图（可选）
                if (hasCover) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      Uint8List.fromList(widget.coverData!),
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                // 歌词文本 — 居中显示
                Text(
                  '「${widget.lyricText}」',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // 分隔线
                Container(
                  width: 40,
                  height: 2,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(height: 16),
                // 歌曲信息
                Text(
                  widget.songTitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.artist,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.album.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.album,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 24),
                // 底部：二维码 + 品牌水印
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 二维码
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: QrImageView(
                        data: kJMusicWebsite,
                        version: QrVersions.auto,
                        size: 52,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black87,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 文字说明
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'JMusic',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '本地音乐播放器',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverBackground() {
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
      child: Image.memory(
        Uint8List.fromList(widget.coverData!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => Container(color: Colors.black),
      ),
    );
  }

  Widget _buildGradientBackground(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.8),
            theme.colorScheme.tertiary.withValues(alpha: 0.6),
            Colors.black87,
          ],
        ),
      ),
    );
  }
}

/// 显示歌词卡片对话框
void showLyricsCardDialog(
  BuildContext context, {
  required String lyricText,
  required String songTitle,
  required String artist,
  String album = '',
  List<int>? coverData,
}) {
  showDialog(
    context: context,
    builder: (_) => LyricsCardDialog(
      lyricText: lyricText,
      songTitle: songTitle,
      artist: artist,
      album: album,
      coverData: coverData,
    ),
  );
}
