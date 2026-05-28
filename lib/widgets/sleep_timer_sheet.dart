import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/sleep_timer.dart';

/// 睡前定时器底部弹窗
class SleepTimerSheet extends ConsumerStatefulWidget {
  const SleepTimerSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const SleepTimerSheet(),
    );
  }

  @override
  ConsumerState<SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends ConsumerState<SleepTimerSheet> {
  int _selectedMinutes = 30;
  int _fadeSeconds = 60;

  static const _presets = [10, 15, 20, 30, 45, 60, 90];

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(sleepTimerProvider);
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
              const Icon(Icons.bedtime_outlined, color: Colors.white70),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '睡前定时',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (timer.isActive)
                TextButton(
                  onPressed: () =>
                      ref.read(sleepTimerProvider.notifier).cancel(),
                  child: const Text('取消',
                      style: TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
          const SizedBox(height: 16),

          if (timer.isActive) ...[
            // 激活状态：显示倒计时
            _buildActiveView(timer, theme),
          ] else ...[
            // 未激活：选择时间
            _buildSetupView(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveView(SleepTimerState timer, ThemeData theme) {
    return Column(
      children: [
        // 倒计时显示
        Text(
          timer.remainingFormatted,
          style: TextStyle(
            color: timer.isFading
                ? Colors.orangeAccent
                : theme.colorScheme.primary,
            fontSize: 48,
            fontWeight: FontWeight.w300,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          timer.isFading ? '正在渐弱...' : '后停止播放',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 20),

        // +5 分钟按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(sleepTimerProvider.notifier).addMinutes(5),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('+5 分钟'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(sleepTimerProvider.notifier).addMinutes(15),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('+15 分钟'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSetupView(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 时间预设
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _presets.map((m) {
            final selected = m == _selectedMinutes;
            return ChoiceChip(
              label: Text('$m 分钟'),
              selected: selected,
              onSelected: (_) => setState(() => _selectedMinutes = m),
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
        const SizedBox(height: 20),

        // 渐弱设置
        Row(
          children: [
            Text(
              '渐弱',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  activeTrackColor: theme.colorScheme.primary,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: theme.colorScheme.primary,
                ),
                child: Slider(
                  value: _fadeSeconds.toDouble(),
                  min: 0,
                  max: 120,
                  divisions: 12,
                  onChanged: (v) =>
                      setState(() => _fadeSeconds = v.toInt()),
                ),
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                _fadeSeconds == 0 ? '关闭' : '${_fadeSeconds}s',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // 开始按钮
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              ref.read(sleepTimerProvider.notifier).start(
                    minutes: _selectedMinutes,
                    fadeSeconds: _fadeSeconds,
                  );
            },
            icon: const Icon(Icons.bedtime, size: 18),
            label: Text('$_selectedMinutes 分钟后停止'),
          ),
        ),
      ],
    );
  }
}
