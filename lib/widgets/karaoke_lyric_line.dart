import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:jmusic/src/rust/models/lyrics.dart';

/// 卡拉OK逐字平滑变色歌词行组件
///
/// 核心特性：
/// 1. 采用本地 Ticker 驱动的 60/120 FPS 毫秒级时间插值，摆脱播放器进度轮询间隔导致的生硬跳变。
/// 2. 具备羽化柔和渐变与微光晕扫光效果，避免机械切刀式的生硬感。
/// 3. 无逐字时间戳或非当前活跃行时全自动优雅降级，零性能开销。
class KaraokeLyricLine extends StatefulWidget {
  /// 歌词行数据
  final LyricLine line;

  /// 当前播放器汇报的播放进度基准（毫秒）
  final int currentMs;

  /// 是否为当前正在播放的行
  final bool isCurrentLine;

  /// 文字排版样式
  final TextStyle textStyle;

  /// 激活/已唱过的颜色
  final Color activeColor;

  /// 未唱到的颜色
  final Color inactiveColor;

  /// 对齐方式
  final TextAlign textAlign;

  const KaraokeLyricLine({
    super.key,
    required this.line,
    required this.currentMs,
    required this.isCurrentLine,
    required this.textStyle,
    required this.activeColor,
    required this.inactiveColor,
    this.textAlign = TextAlign.center,
  });

  @override
  State<KaraokeLyricLine> createState() => _KaraokeLyricLineState();
}

class _KaraokeLyricLineState extends State<KaraokeLyricLine>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;

  /// 最近一次收到外部基准时间的时间戳
  int _anchorMs = 0;
  DateTime _anchorTime = DateTime.now();

  /// 估算推导出的当前毫秒（高帧率平滑递增）
  int _smoothCurrentMs = 0;

  @override
  void initState() {
    super.initState();
    _anchorMs = widget.currentMs;
    _anchorTime = DateTime.now();
    _smoothCurrentMs = widget.currentMs;

    _updateTickerState();
  }

  @override
  void didUpdateWidget(covariant KaraokeLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 基准时间更新或者行改变时同步锚点
    if (oldWidget.currentMs != widget.currentMs ||
        oldWidget.line != widget.line) {
      _anchorMs = widget.currentMs;
      _anchorTime = DateTime.now();
      _smoothCurrentMs = widget.currentMs;
    }

    _updateTickerState();
  }

  /// 根据是否为当前行和是否有逐字歌词动态管理 Ticker
  void _updateTickerState() {
    final hasWords =
        widget.line.words != null && widget.line.words!.isNotEmpty;
    final shouldTick = widget.isCurrentLine && hasWords;

    if (shouldTick) {
      if (_ticker == null) {
        _ticker = createTicker(_onTick);
        _ticker!.start();
      } else if (!_ticker!.isActive) {
        _ticker!.start();
      }
    } else {
      _ticker?.stop();
    }
  }

  /// 每一帧按真实流逝时间推算微秒插值，实现 60/120 FPS 丝滑变色
  void _onTick(Duration elapsed) {
    if (!mounted || !widget.isCurrentLine) return;

    final realElapsedMs =
        DateTime.now().difference(_anchorTime).inMilliseconds;
    // 容差控制：最多往前平滑外推 300ms，防止暂停后持续无限制狂飙
    final estimated = _anchorMs + realElapsedMs.clamp(0, 300);

    if (estimated != _smoothCurrentMs) {
      setState(() {
        _smoothCurrentMs = estimated;
      });
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.line.words;

    // 如果该行没有逐字时间戳，或不是当前活跃行，直接降级为普通文本
    if (words == null || words.isEmpty || !widget.isCurrentLine) {
      return Text(
        widget.line.text,
        textAlign: widget.textAlign,
        style: widget.textStyle.copyWith(
          color: widget.isCurrentLine ? widget.activeColor : widget.inactiveColor,
        ),
      );
    }

    final displayMs = _smoothCurrentMs;

    // 映射 Wrap 的对齐方式
    final wrapAlignment = switch (widget.textAlign) {
      TextAlign.left || TextAlign.start => WrapAlignment.start,
      TextAlign.right || TextAlign.end => WrapAlignment.end,
      _ => WrapAlignment.center,
    };

    // 确保逐字渲染时不携带文本阴影，防止 ShaderMask 对单字矩形边界裁剪阴影产生半透明暗块
    final baseStyle = widget.textStyle.copyWith(shadows: const []);

    return Wrap(
      alignment: wrapAlignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: words.map((w) {
        final startMs = w.startMs.toInt();
        final durationMs = w.durationMs.toInt().clamp(1, 9999999);
        final endMs = startMs + durationMs;

        // 1. 已完全唱过：全激活色
        if (displayMs >= endMs) {
          return Text(
            w.text,
            style: baseStyle.copyWith(color: widget.activeColor),
          );
        }

        // 2. 尚未唱到：全暗色
        if (displayMs < startMs) {
          return Text(
            w.text,
            style: baseStyle.copyWith(color: widget.inactiveColor),
          );
        }

        // 3. 当前字正在唱中：计算该字在当前时间的完成比例 (0.0 ~ 1.0)
        final progress =
            ((displayMs - startMs) / durationMs).clamp(0.0, 1.0);

        // 边缘羽化带宽度（0.12 = 12% 字符宽度），消除生硬切割线
        const feather = 0.12;
        final startStop = (progress - feather).clamp(0.0, 1.0);
        final endStop = (progress + feather).clamp(0.0, 1.0);

        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [
                0.0,
                startStop,
                endStop,
                1.0,
              ],
              colors: [
                widget.activeColor,
                widget.activeColor,
                widget.inactiveColor,
                widget.inactiveColor,
              ],
            ).createShader(bounds);
          },
          child: Text(
            w.text,
            style: baseStyle.copyWith(color: Colors.white),
          ),
        );
      }).toList(),
    );
  }
}
