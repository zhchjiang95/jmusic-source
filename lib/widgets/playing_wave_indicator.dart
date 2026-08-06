import 'package:flutter/material.dart';

/// 动态律动音波指示器（用于歌曲列表中展示“正在播放”跳动波形）
class PlayingWaveIndicator extends StatefulWidget {
  final Color color;
  final bool isPlaying;
  final double height;
  final double width;
  final int barCount;

  const PlayingWaveIndicator({
    super.key,
    required this.color,
    this.isPlaying = true,
    this.height = 14,
    this.width = 16,
    this.barCount = 3,
  });

  @override
  State<PlayingWaveIndicator> createState() => _PlayingWaveIndicatorState();
}

class _PlayingWaveIndicatorState extends State<PlayingWaveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );

    if (widget.isPlaying) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant PlayingWaveIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barWidth = (widget.width - (widget.barCount - 1) * 2.5) / widget.barCount;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(widget.barCount, (index) {
              // 为不同的音波条计算相位相干高度（使得 3 根柱子交错跳动）
              final phase = (index * 0.33) % 1.0;
              final animValue = (_controller.value + phase) % 1.0;

              // 当暂停时，高度固定在较低水平；播放时在 0.25 到 1.0 之间跳动
              final scale = widget.isPlaying
                  ? 0.25 + 0.75 * (0.5 - (animValue - 0.5).abs()) * 2
                  : 0.25;

              final currentHeight = (widget.height * scale).clamp(3.0, widget.height);

              return Container(
                width: barWidth,
                height: currentHeight,
                decoration: BoxDecoration(
                  color: widget.isPlaying
                      ? widget.color
                      : widget.color.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
