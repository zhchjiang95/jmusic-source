import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 浮动粒子背景 — 半透明光点缓慢飘动
class ParticlesBackground extends StatefulWidget {
  final int count;
  final Color color;
  final bool active;

  const ParticlesBackground({
    super.key,
    this.count = 30,
    this.color = Colors.white,
    this.active = true,
  });

  @override
  State<ParticlesBackground> createState() => _ParticlesBackgroundState();
}

class _ParticlesBackgroundState extends State<ParticlesBackground>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  late List<_Particle> _particles;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _particles = List.generate(widget.count, (_) => _randomParticle());
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  _Particle _randomParticle() {
    return _Particle(
      x: _random.nextDouble(),
      y: _random.nextDouble(),
      vx: (_random.nextDouble() - 0.5) * 0.0003,
      vy: -_random.nextDouble() * 0.0004 - 0.0001,
      radius: _random.nextDouble() * 2.5 + 1.0,
      alpha: _random.nextDouble() * 0.4 + 0.1,
    );
  }

  void _onTick(Duration elapsed) {
    if (!widget.active) return;
    bool changed = false;
    for (var p in _particles) {
      p.x += p.vx;
      p.y += p.vy;
      // 超出边界则重置
      if (p.y < -0.05 || p.x < -0.05 || p.x > 1.05) {
        p.x = _random.nextDouble();
        p.y = 1.05;
        p.vx = (_random.nextDouble() - 0.5) * 0.0003;
        p.vy = -_random.nextDouble() * 0.0004 - 0.0001;
      }
      changed = true;
    }
    if (changed) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ParticlesPainter(
          particles: _particles,
          color: widget.color,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _Particle {
  double x, y, vx, vy, radius, alpha;
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.alpha,
  });
}

class _ParticlesPainter extends CustomPainter {
  final List<_Particle> particles;
  final Color color;

  _ParticlesPainter({required this.particles, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = color.withValues(alpha: p.alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter old) => true;
}
