import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 黑胶唱片旋转封面 — 播放时匀速旋转，暂停时停止
class VinylDisc extends StatefulWidget {
  final List<int>? coverData;
  final bool isPlaying;
  final double size;

  const VinylDisc({
    super.key,
    required this.coverData,
    required this.isPlaying,
    this.size = 280,
  });

  @override
  State<VinylDisc> createState() => _VinylDiscState();
}

class _VinylDiscState extends State<VinylDisc>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant VinylDisc old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * pi,
          child: child,
        );
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 黑胶底盘
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.grey.shade900,
                    Colors.black,
                    Colors.grey.shade900,
                    Colors.black87,
                  ],
                  stops: const [0.0, 0.3, 0.6, 1.0],
                ),
              ),
              // 唱片纹路
              child: CustomPaint(
                painter: _GroovePainter(),
              ),
            ),
            // 封面（中心圆形）
            ClipOval(
              child: SizedBox(
                width: widget.size * 0.42,
                height: widget.size * 0.42,
                child: widget.coverData != null
                    ? Image.memory(
                        Uint8List.fromList(widget.coverData!),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.primary.withValues(alpha: 0.6),
                              theme.colorScheme.tertiary.withValues(alpha: 0.6),
                            ],
                          ),
                        ),
                        child: const Icon(Icons.music_note,
                            size: 40, color: Colors.white54),
                      ),
              ),
            ),
            // 中心圆点
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.shade300,
                border: Border.all(color: Colors.grey.shade600, width: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 唱片纹路绘制
class _GroovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withValues(alpha: 0.06);

    // 绘制同心圆纹路
    for (double r = maxRadius * 0.28; r < maxRadius * 0.95; r += 3.0) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
