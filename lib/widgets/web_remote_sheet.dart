import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/web_remote_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Web 遥控底部弹窗 — 显示开关、QR 码和连接状态
class WebRemoteSheet extends ConsumerWidget {
  const WebRemoteSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const WebRemoteSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(webRemoteProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // 标题 + 开关
          Row(
            children: [
              const Icon(Icons.wifi_tethering, color: Colors.white70),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Web 遥控',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch(
                value: remote.isRunning,
                onChanged: (_) =>
                    ref.read(webRemoteProvider.notifier).toggle(),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Text(
            '开启后，同一局域网内的手机浏览器可扫码控制播放',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),

          // QR 码 + URL
          if (remote.isRunning && remote.url != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: remote.url!,
                version: QrVersions.auto,
                size: 135,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              remote.url!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${remote.clientCount} 个设备已连接',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
