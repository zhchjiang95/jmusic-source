import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:jmusic/providers/spectrum.dart';

/// 频谱可视化组件 — 支持 bars（柱状）和 ring（环形）两种样式。
///
/// 通过内部 Ticker 在两帧之间做线性插值，实现 60 FPS 平滑动画。
class SpectrumView extends StatefulWidget {
  final SpectrumStyle style;
  final List<double> spectrum;
  final double opacity;
  final Color? color;

  const SpectrumView({
    super.key,
    required this.style,
    required this.spectrum,
    this.opacity = 1.0,
    this.color,
  });

  @override
  State<SpectrumView> createState() => _SpectrumViewState();
}

class _SpectrumViewState extends State<SpectrumView>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  List<double> _prev = List.filled(kSpectrumBins, 0.0);
  List<double> _target = List.filled(kSpectrumBins, 0.0);
  List<double> _displayed = List.filled(kSpectrumBins, 0.0);
  Duration _lastFrameTime = Duration.zero;
  Duration _lastElapsed = Duration.zero;
  static const _window = kSpectrumPollInterval; // 50ms

  @override
  void initState() {
    super.initState();
    _target = _normalize(widget.spectrum);
    _displayed = List.of(_target);
    _prev = List.of(_target);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant SpectrumView old) {
    super.didUpdateWidget(old);
    if (!identical(old.spectrum, widget.spectrum)) {
      _prev = List.of(_displayed);
      _target = _normalize(widget.spectrum);
      _lastFrameTime = _lastElapsed;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  List<double> _normalize(List<double> s) {
    if (s.length == kSpectrumBins) return List.of(s);
    return List<double>.generate(
        kSpectrumBins, (i) => i < s.length ? s[i].clamp(0.0, 1.0) : 0.0);
  }

  void _onTick(Duration elapsed) {
    _lastElapsed = elapsed;
    final dt = (elapsed - _lastFrameTime).inMicroseconds /
        _window.inMicroseconds.toDouble();
    final t = dt.clamp(0.0, 1.0);
    bool changed = false;
    for (var i = 0; i < kSpectrumBins; i++) {
      final v = _prev[i] + (_target[i] - _prev[i]) * t;
      if (v != _displayed[i]) {
        _displayed[i] = v;
        changed = true;
      }
    }
    if (changed) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ?? Theme.of(context).colorScheme.primary;
    return RepaintBoundary(
      child: CustomPaint(
        painter: widget.style == SpectrumStyle.bars
            ? _BarsPainter(
                spectrum: _displayed,
                color: color,
                opacity: widget.opacity,
              )
            : _RingPainter(
                spectrum: _displayed,
                color: color,
                opacity: widget.opacity,
              ),
        size: Size.infinite,
      ),
    );
  }
}

// ─── Bars Painter ────────────────────────────────────────────────────────────

class _BarsPainter extends CustomPainter {
  final List<double> spectrum;
  final Color color;
  final double opacity;

  _BarsPainter({
    required this.spectrum,
    required this.color,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bins = spectrum.length;
    if (bins == 0) return;

    const gap = 2.0;
    final barWidth = (size.width - (bins - 1) * gap) / bins;
    if (barWidth <= 0) return;

    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < bins; i++) {
      final m = spectrum[i].clamp(0.0, 1.0);
      final barHeight = max(2.0, m * size.height);
      final x = i * (barWidth + gap);
      final y = size.height - barHeight;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => true;
}

// ─── Ring Painter ────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final List<double> spectrum;
  final Color color;
  final double opacity;

  _RingPainter({
    required this.spectrum,
    required this.color,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bins = spectrum.length;
    if (bins == 0) return;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseRadius = min(size.width, size.height) * 0.32;
    final maxBar = min(size.width, size.height) * 0.18;
    final segmentAngle = 2 * pi / bins;
    final gapAngle = segmentAngle * 0.15;
    final drawAngle = segmentAngle - gapAngle;

    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(2.0, drawAngle * baseRadius * 0.6)
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(cx, cy);

    for (var i = 0; i < bins; i++) {
      final m = spectrum[i].clamp(0.0, 1.0);
      final startAngle = -pi / 2 + i * segmentAngle + gapAngle / 2;
      final r = baseRadius + maxBar * m;

      final rect = Rect.fromCircle(center: Offset.zero, radius: r);
      canvas.drawArc(rect, startAngle, drawAngle, false, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => true;
}
