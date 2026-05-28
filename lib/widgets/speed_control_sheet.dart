import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/playback_speed.dart';

/// 变速控制底部弹窗
class SpeedControlSheet extends ConsumerWidget {
  const SpeedControlSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const SpeedControlSheet(),
    );
  }

  static const _presets = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(playbackSpeedProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 标题
          Row(
            children: [
              const Icon(Icons.speed, color: Colors.white70),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '播放速度',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (speed != 1.0)
                TextButton(
                  onPressed: () =>
                      ref.read(playbackSpeedProvider.notifier).reset(),
                  child: const Text('重置',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // 当前速度显示
          Text(
            '${speed.toStringAsFixed(2)}x',
            style: TextStyle(
              color: speed == 1.0
                  ? Colors.white
                  : theme.colorScheme.primary,
              fontSize: 36,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 24),

          // 滑块
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 8),
              activeTrackColor: theme.colorScheme.primary,
              inactiveTrackColor: Colors.white12,
              thumbColor: theme.colorScheme.primary,
            ),
            child: Slider(
              value: speed,
              min: 0.5,
              max: 2.0,
              divisions: 30, // 0.05 步进
              onChanged: (v) {
                // 吸附到预设值
                final snapped = _snapToPreset(v);
                ref.read(playbackSpeedProvider.notifier).setSpeed(snapped);
              },
            ),
          ),

          // 刻度标签
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0.5x',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11)),
                Text('1.0x',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11)),
                Text('2.0x',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 预设按钮
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((p) {
              final selected = (speed - p).abs() < 0.01;
              return ChoiceChip(
                label: Text('${p}x'),
                selected: selected,
                onSelected: (_) =>
                    ref.read(playbackSpeedProvider.notifier).setSpeed(p),
                selectedColor: theme.colorScheme.primary,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 13,
                ),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                side: BorderSide.none,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 吸附到最近的预设值（容差 0.03）
  double _snapToPreset(double value) {
    for (final p in _presets) {
      if ((value - p).abs() < 0.03) return p;
    }
    return double.parse(value.toStringAsFixed(2));
  }
}
