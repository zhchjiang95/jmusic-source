import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/src/rust/models/lyrics.dart';

/// 逐字打轴可编辑字单元
class _EditableWord {
  String text;
  int startMs;
  int durationMs;
  bool isStamped;

  _EditableWord({
    required this.text,
    this.startMs = 0,
    this.durationMs = 400,
    this.isStamped = false,
  });

  int get endMs => startMs + durationMs;
}

/// 逐字时间戳编辑与打轴对话框
///
/// 核心支持：
/// 1. 伴随播放按空格键逐字推进打轴（Tap-to-sync）
/// 2. 提前 2 秒前奏预备起播试听，避免进唱猝不及防
/// 3. 人耳反应延迟自动补偿（默认提前 150ms 记录）
/// 4. 60 FPS 柔和羽化卡拉OK实时变色预览与进唱倒计时
/// 5. 打轴后一键整体偏移（+/- 50ms, +/- 100ms）及单字微调
class WordSyncDialog extends ConsumerStatefulWidget {
  /// 当前行文本
  final String lineText;

  /// 当前行起始时间（毫秒）
  final int lineTimeMs;

  /// 现有已打轴数据（若有）
  final List<LyricWord>? initialWords;

  /// 默认反应延迟补偿量（毫秒）
  final int defaultReactionOffsetMs;

  const WordSyncDialog({
    super.key,
    required this.lineText,
    required this.lineTimeMs,
    this.initialWords,
    this.defaultReactionOffsetMs = 150,
  });

  @override
  ConsumerState<WordSyncDialog> createState() => _WordSyncDialogState();
}

class _WordSyncDialogState extends ConsumerState<WordSyncDialog>
    with SingleTickerProviderStateMixin {
  late List<_EditableWord> _words;
  late int _reactionOffsetMs;
  int _activeWordIndex = 0;
  final FocusNode _focusNode = FocusNode();

  Ticker? _ticker;
  int _anchorMs = 0;
  DateTime _anchorTime = DateTime.now();
  int _smoothCurrentMs = 0;

  @override
  void initState() {
    super.initState();
    _reactionOffsetMs = widget.defaultReactionOffsetMs;
    _initWords();

    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final isPlaying = ref.read(playerProvider).isPlaying;
    if (isPlaying) {
      final realElapsed =
          DateTime.now().difference(_anchorTime).inMilliseconds;
      final estimated = _anchorMs + realElapsed.clamp(0, 300);
      if (estimated != _smoothCurrentMs) {
        setState(() {
          _smoothCurrentMs = estimated;
        });
      }
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 初始化分词列表
  void _initWords() {
    if (widget.initialWords != null && widget.initialWords!.isNotEmpty) {
      _words = widget.initialWords!.map((w) {
        return _EditableWord(
          text: w.text,
          startMs: w.startMs.toInt(),
          durationMs: w.durationMs.toInt(),
          isStamped: true,
        );
      }).toList();
      _activeWordIndex = 0;
    } else {
      // 智能分词：汉字单独切分，连续英文字母/数字切为一个词
      _words = _splitWords(widget.lineText).map((t) {
        return _EditableWord(text: t, isStamped: false);
      }).toList();
      _activeWordIndex = 0;
    }
  }

  /// 智能切词规则
  List<String> _splitWords(String text) {
    final result = <String>[];
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final code = char.codeUnitAt(0);
      final isAsciiAlphaNumeric =
          (code >= 65 && code <= 90) ||
          (code >= 97 && code <= 122) ||
          (code >= 48 && code <= 57);

      if (isAsciiAlphaNumeric) {
        buffer.write(char);
      } else {
        if (buffer.isNotEmpty) {
          result.add(buffer.toString());
          buffer.clear();
        }
        if (char.trim().isNotEmpty) {
          result.add(char);
        }
      }
    }
    if (buffer.isNotEmpty) {
      result.add(buffer.toString());
    }
    return result.isEmpty ? [text] : result;
  }

  /// 敲击打轴（支持空格键或点击打轴按钮触发）
  void _stampNext() {
    if (_words.isEmpty) return;

    final currentPositionMs =
        ref.read(playerProvider).position.inMilliseconds;
    // 应用人耳生理反应延迟补偿（提前 _reactionOffsetMs 记录真实时间）
    final compensatedTime =
        (currentPositionMs - _reactionOffsetMs).clamp(0, 99999999);

    setState(() {
      if (_activeWordIndex < _words.length) {
        // 结束前一个字的持续时间
        if (_activeWordIndex > 0) {
          final prevWord = _words[_activeWordIndex - 1];
          final calculatedDuration = compensatedTime - prevWord.startMs;
          prevWord.durationMs = calculatedDuration.clamp(50, 10000);
        }

        // 记录当前字的开始时间
        _words[_activeWordIndex].startMs = compensatedTime;
        _words[_activeWordIndex].durationMs = 400; // 默认给 400ms 持续时间
        _words[_activeWordIndex].isStamped = true;

        _activeWordIndex++;
      } else {
        // 如果已经打完最后一个字，再次敲击记录该字结束时间
        if (_words.isNotEmpty) {
          final lastWord = _words.last;
          final calculatedDuration = compensatedTime - lastWord.startMs;
          lastWord.durationMs = calculatedDuration.clamp(50, 10000);
        }
      }
    });
  }

  /// 整行字时间戳一键整体偏移（平移毫秒数）
  void _shiftAllWords(int deltaMs) {
    setState(() {
      for (final w in _words) {
        if (w.isStamped) {
          w.startMs = (w.startMs + deltaMs).clamp(0, 99999999);
        }
      }
    });
  }

  /// 单个字时间微调
  void _adjustWordTime(int index, int deltaMs) {
    setState(() {
      final w = _words[index];
      w.startMs = (w.startMs + deltaMs).clamp(0, 99999999);
      w.isStamped = true;
    });
  }

  /// 单个字持续时间微调
  void _adjustWordDuration(int index, int deltaMs) {
    setState(() {
      final w = _words[index];
      w.durationMs = (w.durationMs + deltaMs).clamp(50, 10000);
    });
  }

  /// 重置打轴数据
  void _resetStamps() {
    setState(() {
      for (final w in _words) {
        w.isStamped = false;
        w.startMs = 0;
        w.durationMs = 400;
      }
      _activeWordIndex = 0;
    });
  }

  /// 从本行起播试听（往前提前 2 秒缓冲准备）
  void _playFromStart() {
    final startTime = _words.isNotEmpty && _words.first.isStamped
        ? _words.first.startMs
        : widget.lineTimeMs;
    // 默认往前提前 2000ms（2秒），让人耳有充分前奏准备时间
    final targetSeekMs = (startTime - 2000).clamp(0, 99999999);
    ref.read(playerProvider.notifier).seekTo(Duration(milliseconds: targetSeekMs));
    if (!ref.read(playerProvider).isPlaying) {
      ref.read(playerProvider.notifier).togglePlayPause();
    }
    _focusNode.requestFocus();
  }

  /// 转换为 LyricWord 列表
  List<LyricWord> _collectWords() {
    return _words.map((w) {
      return LyricWord(
        text: w.text,
        startMs: BigInt.from(w.startMs),
        durationMs: BigInt.from(w.durationMs),
      );
    }).toList();
  }

  /// 格式化时间
  String _formatMs(int ms) {
    final minutes = ms ~/ 60000;
    final seconds = (ms % 60000) / 1000;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toStringAsFixed(2).padLeft(5, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawPosMs = ref.watch(
      playerProvider.select((s) => s.position.inMilliseconds),
    );
    final isPlaying = ref.watch(
      playerProvider.select((s) => s.isPlaying),
    );

    // 同步基准锚点
    if (rawPosMs != _anchorMs) {
      _anchorMs = rawPosMs;
      _anchorTime = DateTime.now();
      _smoothCurrentMs = rawPosMs;
    }

    final currentPosMs = _smoothCurrentMs;

    // 计算首字开始时间
    final firstStartMs = _words.isNotEmpty && _words.first.isStamped
        ? _words.first.startMs
        : widget.lineTimeMs;
    final isPreparing = isPlaying && currentPosMs < firstStartMs;
    final prepareCountdown =
        ((firstStartMs - currentPosMs) / 1000.0).clamp(0.0, 9.9);

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.space) {
          _stampNext();
        }
      },
      child: Dialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          width: 680,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题与操作栏
              Row(
                children: [
                  Icon(
                    Icons.mic_external_on_rounded,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '逐字时间戳编辑与打轴',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20, color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 播放与卡拉OK实时预览区
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  children: [
                    // 状态提示栏（固定高度 26px，消除进唱时提示消失导致的布局跳动）
                    SizedBox(
                      height: 26,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: isPreparing
                              ? Container(
                                  key: const ValueKey('preparing'),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.amber.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.hourglass_top_rounded,
                                        size: 13,
                                        color: Colors.amber,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        '预备进唱中... 倒数 ${prepareCountdown.toStringAsFixed(1)}s (准备按空格打轴)',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.amber,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : isPlaying
                                  ? Container(
                                      key: const ValueKey('singing'),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: theme.colorScheme.primary.withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.mic_rounded,
                                            size: 13,
                                            color: theme.colorScheme.primary,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            '演唱进行中... 伴随人声按 [空格键] 或点击下方按钮打轴',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Container(
                                      key: const ValueKey('idle'),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.1),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.info_outline,
                                            size: 13,
                                            color: Colors.white54,
                                          ),
                                          SizedBox(width: 5),
                                          Text(
                                            '点击“提前 2 秒起播试听”或播放后，按 [空格键] 逐字打轴',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.white54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 实时卡拉OK渐变预览条（柔和羽化与发光微晕）
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: _words.map((w) {
                        if (!w.isStamped) {
                          return Text(
                            w.text,
                            style: const TextStyle(
                              fontSize: 22,
                              color: Colors.white24,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }
                        if (currentPosMs >= w.endMs) {
                          return Text(
                            w.text,
                            style: TextStyle(
                              fontSize: 22,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }
                        if (currentPosMs < w.startMs) {
                          return Text(
                            w.text,
                            style: const TextStyle(
                              fontSize: 22,
                              color: Colors.white38,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }
                        // 正在唱的字，使用 12% 羽化带与微光晕柔化渐变
                        final p = ((currentPosMs - w.startMs) / w.durationMs)
                            .clamp(0.0, 1.0);
                        const feather = 0.12;
                        final startStop = (p - feather).clamp(0.0, 1.0);
                        final endStop = (p + feather).clamp(0.0, 1.0);
                        final glow = Color.lerp(
                          theme.colorScheme.primary,
                          Colors.white,
                          0.45,
                        )!;

                        return ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              stops: [0.0, startStop, p, endStop, 1.0],
                              colors: [
                                theme.colorScheme.primary,
                                theme.colorScheme.primary,
                                glow,
                                Colors.white38,
                                Colors.white38,
                              ],
                            ).createShader(bounds);
                          },
                          child: Text(
                            w.text,
                            style: const TextStyle(
                              fontSize: 22,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    // 播放控制器快捷按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _playFromStart,
                          icon: Icon(
                            isPlaying ? Icons.replay : Icons.play_arrow,
                            size: 16,
                          ),
                          label: const Text('提前 2 秒起播试听'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '当前进度: ${_formatMs(currentPosMs)}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 核心打轴控制器 & 人耳反应延迟补偿设置
              Row(
                children: [
                  // 打轴主操作按钮（固定高度 48px，按空格键也能触发）
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _stampNext();
                          _focusNode.requestFocus();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.touch_app, size: 20),
                        label: Text(
                          _activeWordIndex < _words.length
                              ? '跟着演唱敲击 [空格键] (字 ${_activeWordIndex + 1}/${_words.length}: "${_words[_activeWordIndex].text}")'
                              : '已打完最后一个字 (按空格锁定时长)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 人耳生理反应延迟补偿
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: PopupMenuButton<int>(
                      tooltip: '设置按键反应延迟补偿',
                      initialValue: _reactionOffsetMs,
                      onSelected: (val) {
                        setState(() => _reactionOffsetMs = val);
                        _focusNode.requestFocus();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 0, child: Text('无补偿 (0ms)')),
                        const PopupMenuItem(value: 100, child: Text('补偿 -100ms')),
                        const PopupMenuItem(
                          value: 150,
                          child: Text('补偿 -150ms (推荐生理延迟)'),
                        ),
                        const PopupMenuItem(value: 200, child: Text('补偿 -200ms')),
                        const PopupMenuItem(value: 300, child: Text('补偿 -300ms')),
                      ],
                      child: Row(
                        children: [
                          const Icon(Icons.speed, size: 16, color: Colors.amber),
                          const SizedBox(width: 6),
                          Text(
                            '延迟补偿: -${_reactionOffsetMs}ms',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _resetStamps,
                    icon: const Icon(Icons.restart_alt, color: Colors.white54),
                    tooltip: '重置此行打轴',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 整体偏移工具栏（打轴完成后微调，满足用户核心需求）
              Row(
                children: [
                  const Text(
                    '整行字时间平移:',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(width: 8),
                  _buildOffsetPill(
                    '-100ms',
                    () => _shiftAllWords(-100),
                    tooltip: '整行所有字提前 100ms',
                  ),
                  const SizedBox(width: 6),
                  _buildOffsetPill(
                    '-50ms',
                    () => _shiftAllWords(-50),
                    tooltip: '整行所有字提前 50ms',
                  ),
                  const SizedBox(width: 6),
                  _buildOffsetPill(
                    '+50ms',
                    () => _shiftAllWords(50),
                    tooltip: '整行所有字延后 50ms',
                  ),
                  const SizedBox(width: 6),
                  _buildOffsetPill(
                    '+100ms',
                    () => _shiftAllWords(100),
                    tooltip: '整行所有字延后 100ms',
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 详细字列表卡片与单字时间微调
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _words.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                    itemBuilder: (context, i) {
                      final w = _words[i];
                      final isCurrent = i == _activeWordIndex;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? theme.colorScheme.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            // 序号
                            Text(
                              '${i + 1}.',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white30,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 单字文本
                            SizedBox(
                              width: 50,
                              child: Text(
                                w.text,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: w.isStamped
                                      ? theme.colorScheme.primary
                                      : Colors.white70,
                                ),
                              ),
                            ),
                            // 起始时间戳
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                w.isStamped ? _formatMs(w.startMs) : '--:--.--',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: w.isStamped
                                      ? Colors.white
                                      : Colors.white24,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // 起始时间微调
                            _miniAdjBtn(
                              Icons.remove,
                              () => _adjustWordTime(i, -50),
                              tooltip: '提前 50ms',
                            ),
                            _miniAdjBtn(
                              Icons.add,
                              () => _adjustWordTime(i, 50),
                              tooltip: '延后 50ms',
                            ),
                            const SizedBox(width: 14),
                            // 持续时间
                            Text(
                              '持续: ${w.durationMs}ms',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white54,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 6),
                            _miniAdjBtn(
                              Icons.remove,
                              () => _adjustWordDuration(i, -50),
                              tooltip: '缩短 50ms',
                            ),
                            _miniAdjBtn(
                              Icons.add,
                              () => _adjustWordDuration(i, 50),
                              tooltip: '延长 50ms',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 底部动作按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      final hasAnyStamped = _words.any((w) => w.isStamped);
                      if (hasAnyStamped) {
                        Navigator.of(context).pop(_collectWords());
                      } else {
                        Navigator.of(context).pop(<LyricWord>[]);
                      }
                    },
                    child: const Text('应用并保存此行逐字轴'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 偏移标签胶囊按钮
  Widget _buildOffsetPill(String label, VoidCallback onTap, {String? tooltip}) {
    Widget pill = InkWell(
      onTap: () {
        onTap();
        _focusNode.requestFocus();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white70,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
    if (tooltip != null) {
      pill = Tooltip(message: tooltip, child: pill);
    }
    return pill;
  }

  /// 微型微调按钮
  Widget _miniAdjBtn(IconData icon, VoidCallback onTap, {String? tooltip}) {
    Widget btn = InkWell(
      onTap: () {
        onTap();
        _focusNode.requestFocus();
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 12, color: Colors.white70),
      ),
    );
    if (tooltip != null) {
      btn = Tooltip(message: tooltip, child: btn);
    }
    return btn;
  }
}
