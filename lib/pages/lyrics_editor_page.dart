import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/src/rust/api/metadata.dart' as rust_metadata;

/// 歌词编辑器页面 — 手动调时间轴的 LRC 编辑器
/// 支持：逐行打轴、手动微调时间、编辑歌词文本、导入/导出 LRC
class LyricsEditorPage extends ConsumerStatefulWidget {
  const LyricsEditorPage({super.key});

  @override
  ConsumerState<LyricsEditorPage> createState() => _LyricsEditorPageState();
}

class _LyricsEditorPageState extends ConsumerState<LyricsEditorPage> {
  /// 编辑中的歌词行列表
  List<_EditableLine> _lines = [];

  /// 当前正在打轴的行索引
  int _currentStampIndex = 0;

  /// 是否有未保存的修改
  bool _isDirty = false;

  /// 滚动控制器
  final ScrollController _scrollController = ScrollController();

  /// 全局 key 列表，用于滚动定位
  List<GlobalKey> _lineKeys = [];

  @override
  void initState() {
    super.initState();
    _loadFromPlayer();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 从当前播放器状态加载歌词
  void _loadFromPlayer() {
    final playerState = ref.read(playerProvider);
    if (playerState.lyrics != null && playerState.lyrics!.lines.isNotEmpty) {
      _lines = playerState.lyrics!.lines.map((line) {
        return _EditableLine(
          timeMs: line.timeMs.toInt(),
          text: line.text,
        );
      }).toList();
    } else if (playerState.lrcText != null &&
        playerState.lrcText!.trim().isNotEmpty) {
      // 从原始 LRC 文本解析
      final parsed = rust_metadata.parseLrcText(lrcText: playerState.lrcText!);
      _lines = parsed.lines.map((line) {
        return _EditableLine(
          timeMs: line.timeMs.toInt(),
          text: line.text,
        );
      }).toList();
    }
    _lineKeys = List.generate(_lines.length, (_) => GlobalKey());
    _currentStampIndex = 0;
  }

  /// 从纯文本导入（无时间轴）
  void _importPlainText(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    setState(() {
      _lines = lines.map((l) => _EditableLine(timeMs: 0, text: l.trim())).toList();
      _lineKeys = List.generate(_lines.length, (_) => GlobalKey());
      _currentStampIndex = 0;
      _isDirty = true;
    });
  }

  /// 从 LRC 文本导入
  void _importLrcText(String lrcText) {
    final parsed = rust_metadata.parseLrcText(lrcText: lrcText);
    setState(() {
      _lines = parsed.lines.map((line) {
        return _EditableLine(
          timeMs: line.timeMs.toInt(),
          text: line.text,
        );
      }).toList();
      _lineKeys = List.generate(_lines.length, (_) => GlobalKey());
      _currentStampIndex = 0;
      _isDirty = true;
    });
  }

  /// 导出为 LRC 文本
  String _exportLrc() {
    final buffer = StringBuffer();
    for (final line in _lines) {
      final minutes = line.timeMs ~/ 60000;
      final seconds = (line.timeMs % 60000) / 1000;
      final timeStr =
          '${minutes.toString().padLeft(2, '0')}:${seconds.toStringAsFixed(2).padLeft(5, '0')}';
      buffer.writeln('[$timeStr]${line.text}');
    }
    return buffer.toString();
  }

  /// 打轴：将当前播放位置设为指定行的时间戳
  void _stampCurrentLine() {
    if (_currentStampIndex >= _lines.length) return;
    final position = ref.read(playerProvider).position;
    setState(() {
      _lines[_currentStampIndex].timeMs = position.inMilliseconds;
      _isDirty = true;
      _currentStampIndex++;
    });
    // 自动滚动到下一行
    if (_currentStampIndex < _lines.length) {
      _scrollToIndex(_currentStampIndex);
    }
  }

  /// 滚动到指定行
  void _scrollToIndex(int index) {
    if (index < 0 || index >= _lineKeys.length) return;
    final key = _lineKeys[index];
    if (key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.3,
      );
    }
  }

  /// 微调时间（毫秒偏移）
  void _adjustTime(int index, int deltaMs) {
    setState(() {
      _lines[index].timeMs = (_lines[index].timeMs + deltaMs).clamp(0, 99999999);
      _isDirty = true;
    });
  }

  /// 添加新行
  void _addLine(int afterIndex) {
    setState(() {
      final newLine = _EditableLine(timeMs: 0, text: '');
      if (afterIndex < _lines.length - 1) {
        _lines.insert(afterIndex + 1, newLine);
      } else {
        _lines.add(newLine);
      }
      _lineKeys = List.generate(_lines.length, (_) => GlobalKey());
      _isDirty = true;
    });
  }

  /// 删除行
  void _removeLine(int index) {
    if (_lines.length <= 1) return;
    setState(() {
      _lines.removeAt(index);
      _lineKeys = List.generate(_lines.length, (_) => GlobalKey());
      if (_currentStampIndex > index) _currentStampIndex--;
      if (_currentStampIndex >= _lines.length) {
        _currentStampIndex = _lines.length - 1;
      }
      _isDirty = true;
    });
  }

  /// 保存歌词到文件
  Future<void> _save() async {
    final playerState = ref.read(playerProvider);
    final song = playerState.currentSong;
    if (song == null) return;

    final lrcText = _exportLrc();
    try {
      await ref.read(libraryProvider.notifier).saveAllMetadataAndUpdate(
            song: song,
            lyricsText: lrcText,
          );
      setState(() => _isDirty = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('歌词已保存并内嵌到文件'),
            duration: Duration(seconds: 2),
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
  }

  /// 应用到播放器（不保存文件，仅更新内存中的歌词）
  void _applyToPlayer() {
    final playerState = ref.read(playerProvider);
    final song = playerState.currentSong;
    if (song == null) return;

    final lrcText = _exportLrc();
    ref.read(playerProvider.notifier).updateCurrentSongLyrics(
          song: song,
          lyricsText: lrcText,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('歌词已应用到播放器'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  /// 全部时间轴偏移
  void _showOffsetDialog() {
    final controller = TextEditingController(text: '0');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('整体时间偏移', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '输入毫秒数（正数延后，负数提前）',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
              ],
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '例如：500 或 -200',
                suffixText: 'ms',
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final offset = int.tryParse(controller.text) ?? 0;
              if (offset != 0) {
                setState(() {
                  for (final line in _lines) {
                    line.timeMs = (line.timeMs + offset).clamp(0, 99999999);
                  }
                  _isDirty = true;
                });
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('应用'),
          ),
        ],
      ),
    );
  }

  /// 显示导入对话框
  void _showImportDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('导入歌词', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 480,
          height: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '粘贴 LRC 格式歌词或纯文本歌词（每行一句）',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: '[00:00.00] 歌词内容\n或\n纯文本歌词（无时间轴）',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
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
        ),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () {
                  final text = controller.text.trim();
                  if (text.isEmpty) return;
                  Navigator.of(ctx).pop();
                  _importLrcText(text);
                },
                child: const Text('作为 LRC 导入'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  final text = controller.text.trim();
                  if (text.isEmpty) return;
                  Navigator.of(ctx).pop();
                  _importPlainText(text);
                },
                child: const Text('作为纯文本导入'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final position = ref.watch(playerProvider.select((s) => s.position));
    final duration = ref.watch(playerProvider.select((s) => s.duration));
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(
          '歌词编辑器${currentSong != null ? " - ${currentSong.title}" : ""}',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          // 导入
          IconButton(
            onPressed: _showImportDialog,
            icon: const Icon(Icons.file_download_outlined, size: 20),
            tooltip: '导入歌词',
          ),
          // 整体偏移
          IconButton(
            onPressed: _lines.isNotEmpty ? _showOffsetDialog : null,
            icon: const Icon(Icons.timer_outlined, size: 20),
            tooltip: '整体时间偏移',
          ),
          // 应用到播放器
          IconButton(
            onPressed: _lines.isNotEmpty ? _applyToPlayer : null,
            icon: const Icon(Icons.play_circle_outline, size: 20),
            tooltip: '应用到播放器（不保存文件）',
          ),
          // 保存
          IconButton(
            onPressed: _isDirty && _lines.isNotEmpty ? _save : null,
            icon: Icon(
              Icons.save,
              size: 20,
              color: _isDirty ? theme.colorScheme.primary : null,
            ),
            tooltip: '保存并内嵌到文件',
          ),
        ],
      ),
      body: Column(
        children: [
          // 播放控制栏
          _buildPlaybackBar(theme, isPlaying, position, duration),
          // 打轴工具栏
          _buildStampToolbar(theme, position),
          // 歌词行列表
          Expanded(
            child: _lines.isEmpty
                ? _buildEmptyState(theme)
                : _buildLinesList(theme),
          ),
        ],
      ),
    );
  }

  /// 播放控制栏
  Widget _buildPlaybackBar(
    ThemeData theme,
    bool isPlaying,
    Duration position,
    Duration duration,
  ) {
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          // 播放/暂停
          IconButton(
            onPressed: () =>
                ref.read(playerProvider.notifier).togglePlayPause(),
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: theme.colorScheme.primary,
              size: 28,
            ),
          ),
          // 当前时间
          Text(
            _formatTime(position.inMilliseconds),
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          // 进度条
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 5),
                  activeTrackColor: theme.colorScheme.primary,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: theme.colorScheme.primary,
                ),
                child: Slider(
                  value: progress,
                  onChanged: (value) {
                    final newPos = Duration(
                      milliseconds:
                          (value * duration.inMilliseconds).toInt(),
                    );
                    ref.read(playerProvider.notifier).seekTo(newPos);
                  },
                ),
              ),
            ),
          ),
          // 总时长
          Text(
            _formatTime(duration.inMilliseconds),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  /// 打轴工具栏
  Widget _buildStampToolbar(ThemeData theme, Duration position) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF151525),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          // 当前打轴进度
          Text(
            '打轴: ${_currentStampIndex + 1}/${_lines.length}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(width: 16),
          // 打轴按钮（核心操作）
          Expanded(
            child: SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                onPressed: _lines.isNotEmpty && _currentStampIndex < _lines.length
                    ? _stampCurrentLine
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.access_time_filled, size: 18),
                label: Text(
                  _currentStampIndex < _lines.length
                      ? '打轴 [${_formatTime(position.inMilliseconds)}]'
                      : '打轴完成',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 重置打轴位置
          IconButton(
            onPressed: () {
              setState(() => _currentStampIndex = 0);
              _scrollToIndex(0);
            },
            icon: const Icon(Icons.restart_alt, size: 20, color: Colors.white54),
            tooltip: '重置打轴位置',
          ),
        ],
      ),
    );
  }

  /// 空状态
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lyrics_outlined, size: 64, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          const Text(
            '暂无歌词内容',
            style: TextStyle(color: Colors.white38, fontSize: 15),
          ),
          const SizedBox(height: 8),
          const Text(
            '点击右上角导入按钮添加歌词',
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _showImportDialog,
            icon: const Icon(Icons.file_download_outlined, size: 18),
            label: const Text('导入歌词'),
          ),
        ],
      ),
    );
  }

  /// 歌词行列表
  Widget _buildLinesList(ThemeData theme) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _lines.length,
      itemBuilder: (context, index) {
        final line = _lines[index];
        final isCurrentStamp = index == _currentStampIndex;
        final isTimestamped = line.timeMs > 0;

        return Container(
          key: _lineKeys.length > index ? _lineKeys[index] : null,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: isCurrentStamp
                ? theme.colorScheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isCurrentStamp
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.4),
                    width: 1,
                  )
                : null,
          ),
          child: _buildLineItem(theme, index, line, isCurrentStamp, isTimestamped),
        );
      },
    );
  }

  /// 单行歌词项
  Widget _buildLineItem(
    ThemeData theme,
    int index,
    _EditableLine line,
    bool isCurrentStamp,
    bool isTimestamped,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 行号
          SizedBox(
            width: 28,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: isCurrentStamp
                    ? theme.colorScheme.primary
                    : Colors.white24,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // 时间戳（可点击跳转）
          GestureDetector(
            onTap: () {
              // 点击时间戳跳转到该位置播放
              if (line.timeMs > 0) {
                ref.read(playerProvider.notifier).seekTo(
                      Duration(milliseconds: line.timeMs),
                    );
              }
            },
            child: Container(
              width: 72,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: isTimestamped
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatTime(line.timeMs),
                style: TextStyle(
                  color: isTimestamped
                      ? theme.colorScheme.primary.withValues(alpha: 0.9)
                      : Colors.white24,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 微调按钮
          _buildAdjustButtons(theme, index),
          const SizedBox(width: 8),
          // 歌词文本（可编辑）
          Expanded(
            child: GestureDetector(
              onTap: () => _editLineText(index),
              child: Text(
                line.text.isEmpty ? '(空行)' : line.text,
                style: TextStyle(
                  color: line.text.isEmpty
                      ? Colors.white24
                      : isCurrentStamp
                          ? Colors.white
                          : Colors.white70,
                  fontSize: 13,
                  fontWeight:
                      isCurrentStamp ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // 操作菜单
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 16, color: Colors.white30),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'stamp', child: Text('设为当前时间')),
              const PopupMenuItem(value: 'edit', child: Text('编辑文本')),
              const PopupMenuItem(value: 'add', child: Text('在下方插入')),
              const PopupMenuItem(value: 'delete', child: Text('删除此行')),
              const PopupMenuItem(value: 'setStampHere', child: Text('从此行开始打轴')),
            ],
            onSelected: (action) {
              switch (action) {
                case 'stamp':
                  final pos = ref.read(playerProvider).position;
                  setState(() {
                    _lines[index].timeMs = pos.inMilliseconds;
                    _isDirty = true;
                  });
                  break;
                case 'edit':
                  _editLineText(index);
                  break;
                case 'add':
                  _addLine(index);
                  break;
                case 'delete':
                  _removeLine(index);
                  break;
                case 'setStampHere':
                  setState(() => _currentStampIndex = index);
                  _scrollToIndex(index);
                  break;
              }
            },
          ),
        ],
      ),
    );
  }

  /// 微调按钮组
  Widget _buildAdjustButtons(ThemeData theme, int index) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // -100ms
        _miniButton(
          icon: Icons.remove,
          onTap: () => _adjustTime(index, -100),
          tooltip: '-100ms',
        ),
        // +100ms
        _miniButton(
          icon: Icons.add,
          onTap: () => _adjustTime(index, 100),
          tooltip: '+100ms',
        ),
      ],
    );
  }

  Widget _miniButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: Icon(icon, size: 14, color: Colors.white38),
        ),
      ),
    );
  }

  /// 编辑歌词文本
  void _editLineText(int index) {
    final controller = TextEditingController(text: _lines[index].text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('编辑第 ${index + 1} 行', style: const TextStyle(fontSize: 15)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: '输入歌词文本',
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
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _lines[index].text = controller.text;
                _isDirty = true;
              });
              Navigator.of(ctx).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 格式化时间（毫秒 → mm:ss.xx）
  String _formatTime(int ms) {
    final minutes = ms ~/ 60000;
    final seconds = (ms % 60000) / 1000;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toStringAsFixed(2).padLeft(5, '0')}';
  }
}

/// 可编辑的歌词行
class _EditableLine {
  int timeMs;
  String text;

  _EditableLine({required this.timeMs, required this.text});
}
