import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:jmusic/src/rust/api/simple.dart' as rust_simple;
import 'package:jmusic/src/rust/models/song.dart';
import 'package:jmusic/providers/webdav_provider.dart';

/// 音频转码导出对话框
class ExportDialog extends ConsumerStatefulWidget {
  final Song song;

  const ExportDialog({super.key, required this.song});

  static void show(BuildContext context, Song song) {
    showDialog(
      context: context,
      barrierDismissible: false, // 转换期间不允许点外部关闭
      builder: (_) => ExportDialog(song: song),
    );
  }

  @override
  ConsumerState<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<ExportDialog> {
  String _selectedFormat = 'mp3';
  bool _isConverting = false;
  bool _isSuccess = false;
  String _statusText = '';
  String? _error;
  String? _outputPath;

  // 格式特性定义
  final Map<String, _FormatDetail> _formats = {
    'mp3': const _FormatDetail(
      title: 'MP3',
      desc: 'MPEG Layer III',
      detail: '高兼容性，压缩率好，适合大多数播放器。',
      icon: Icons.music_note,
    ),
    'flac': const _FormatDetail(
      title: 'FLAC',
      desc: 'Free Lossless Audio Codec',
      detail: '无损压缩，保留所有音频细节，适合高保真设备。',
      icon: Icons.high_quality,
    ),
    'wav': const _FormatDetail(
      title: 'WAV',
      desc: 'Waveform Audio',
      detail: '无损且完全不压缩，文件体积较大。',
      icon: Icons.audiotrack,
    ),
  };

  Future<void> _startExport() async {
    final ext = _selectedFormat.toLowerCase();
    
    // 生成默认文件名：歌手 - 歌名.格式
    String defaultName = '${widget.song.artist} - ${widget.song.title}.$ext';
    // 清洗非法文件名字符
    defaultName = defaultName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    // 1. 让用户选择保存路径
    String? savePath = await FilePicker.platform.saveFile(
      dialogTitle: '选择导出保存路径',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: [ext],
    );

    if (savePath == null) return; // 用户取消

    // 确保有正确的后缀名
    if (!savePath.toLowerCase().endsWith('.$ext')) {
      savePath = '$savePath.$ext';
    }

    setState(() {
      _isConverting = true;
      _error = null;
      _statusText = '初始化转码任务...';
    });

    try {
      // 2. 检查是否为 WebDAV 云端文件，需要下载到本地缓存
      String inputPath = widget.song.filePath;
      if (inputPath.startsWith('webdav://')) {
        setState(() {
          _statusText = '正在下载云端音乐文件...';
        });
        final webDav = ref.read(webDavProvider.notifier);
        inputPath = await webDav.ensureLocalFile(widget.song);
      }

      // 3. 开始转码
      setState(() {
        _statusText = '正在解码并转码为 ${_selectedFormat.toUpperCase()}...';
      });

      await rust_simple.convertAudio(
        inputPath: inputPath,
        outputPath: savePath,
        targetFormat: _selectedFormat,
      );

      setState(() {
        _isConverting = false;
        _isSuccess = true;
        _outputPath = savePath;
      });
    } catch (e) {
      setState(() {
        _isConverting = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openFolder() async {
    if (_outputPath == null) return;
    try {
      if (Platform.isWindows) {
        // Windows 系统下直接选中并高亮该文件
        await Process.run('explorer.exe', ['/select,', _outputPath!]);
      } else if (Platform.isMacOS) {
        // macOS 系统下高亮选中文件
        await Process.run('open', ['-R', _outputPath!]);
      } else {
        // Linux 平台打开所在文件夹目录
        final dir = Directory(_outputPath!).parent.path;
        await Process.run('xdg-open', [dir]);
      }
    } catch (e) {
      debugPrint('打开文件夹失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Dialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                Icon(Icons.transform_rounded, color: primaryColor, size: 24),
                const SizedBox(width: 10),
                Text(
                  '音频格式转换',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 音频信息及转换状态分支
            if (_isConverting)
              _buildProgressView(primaryColor)
            else if (_isSuccess)
              _buildSuccessView(theme, primaryColor)
            else
              _buildSetupView(theme, primaryColor),
          ],
        ),
      ),
    );
  }

  // 1. 设置格式及信息主界面
  Widget _buildSetupView(ThemeData theme, Color primaryColor) {
    final dimColor = Colors.white.withValues(alpha: 0.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 歌曲基本信息
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.song.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.song.artist,
                      style: TextStyle(color: dimColor, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '原始格式: ${widget.song.format.toUpperCase()}',
                    style: TextStyle(
                      color: primaryColor.withValues(alpha: 0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Text(
          '选择转换目标格式',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),

        // 格式卡片选择列表
        ..._formats.entries.map((entry) {
          final isSelected = _selectedFormat == entry.key;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => setState(() => _selectedFormat = entry.key),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? primaryColor.withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.08),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                  color: isSelected
                      ? primaryColor.withValues(alpha: 0.06)
                      : Colors.transparent,
                ),
                child: Row(
                  children: [
                    Icon(
                      entry.value.icon,
                      color: isSelected ? primaryColor : dimColor,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                entry.value.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '(${entry.value.desc})',
                                style: TextStyle(color: dimColor, fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.value.detail,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),

        // 底栏按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                '取消',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _startExport,
              icon: const Icon(Icons.save_alt_rounded, size: 16),
              label: const Text('开始转码导出'),
            ),
          ],
        ),
      ],
    );
  }

  // 2. 转换进度显示界面
  Widget _buildProgressView(Color primaryColor) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Center(
          child: CircularProgressIndicator(
            color: primaryColor,
            strokeWidth: 3.5,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _statusText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '请稍候，这可能需要几秒钟时间，转码在后台独立线程执行...',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // 3. 成功展示界面
  Widget _buildSuccessView(ThemeData theme, Color primaryColor) {
    final dimColor = Colors.white.withValues(alpha: 0.5);

    return Column(
      children: [
        const SizedBox(height: 16),
        const Center(
          child: Icon(
            Icons.check_circle_rounded,
            color: Colors.greenAccent,
            size: 56,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '音频转码导出成功！',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '保存路径:',
                style: TextStyle(color: dimColor, fontSize: 11),
              ),
              const SizedBox(height: 4),
              Text(
                _outputPath ?? '',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: _openFolder,
              icon: Icon(
                Platform.isMacOS ? Icons.folder_shared : Icons.folder_open,
                size: 16,
              ),
              label: Text(Platform.isMacOS ? '在访达中显示' : '打开所在文件夹'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('完成'),
            ),
          ],
        ),
      ],
    );
  }
}

class _FormatDetail {
  final String title;
  final String desc;
  final String detail;
  final IconData icon;

  const _FormatDetail({
    required this.title,
    required this.desc,
    required this.detail,
    required this.icon,
  });
}
