import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/cast_provider.dart';
import 'package:jmusic/services/dlna_service.dart';

/// 投放设备选择面板
class CastSheet extends ConsumerStatefulWidget {
  const CastSheet({super.key});

  @override
  ConsumerState<CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends ConsumerState<CastSheet> {
  @override
  void initState() {
    super.initState();
    // 打开面板时自动开始发现设备
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final castState = ref.read(castProvider);
      if (!castState.isCasting && !castState.isDiscovering) {
        ref.read(castProvider.notifier).startDiscovery();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final castState = ref.watch(castProvider);
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽手柄
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Icon(
                  Icons.cast_rounded,
                  color: castState.isCasting
                      ? theme.colorScheme.primary
                      : Colors.white70,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  castState.isCasting ? '正在投放' : '投放到设备',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (castState.isDiscovering)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  ),
                if (!castState.isCasting)
                  IconButton(
                    onPressed: () {
                      ref.read(castProvider.notifier).startDiscovery();
                    },
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white54,
                      size: 20,
                    ),
                    tooltip: '刷新',
                  ),
              ],
            ),
          ),

          // 已连接设备信息
          if (castState.isCasting) _buildConnectedView(castState, theme),

          // 设备列表
          if (!castState.isCasting) ...[
            if (castState.devices.isEmpty && castState.isDiscovering)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.wifi_find_rounded, color: Colors.white24, size: 48),
                    SizedBox(height: 12),
                    Text(
                      '正在搜索局域网设备...',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  ],
                ),
              )
            else if (castState.devices.isEmpty && !castState.isDiscovering)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    const Icon(Icons.devices_other_rounded,
                        color: Colors.white24, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      '未发现可用设备',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '确保智能音箱/电视与手机在同一局域网',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: castState.devices.length,
                  itemBuilder: (context, index) {
                    final device = castState.devices[index];
                    return _buildDeviceItem(device, castState, theme);
                  },
                ),
              ),
          ],

          // 错误信息
          if (castState.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        castState.error!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 设备列表项
  Widget _buildDeviceItem(
    DlnaDevice device,
    CastState castState,
    ThemeData theme,
  ) {
    final isConnecting =
        castState.connectionState == CastConnectionState.connecting &&
            castState.activeDevice?.usn == device.usn;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isConnecting
              ? null
              : () {
                  ref.read(castProvider.notifier).connectToDevice(device);
                },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getDeviceIcon(device.friendlyName),
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.friendlyName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        device.address.address,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isConnecting)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  )
                else
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withValues(alpha: 0.3),
                    size: 16,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 已连接状态视图
  Widget _buildConnectedView(CastState castState, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          // 设备信息
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getDeviceIcon(castState.activeDevice?.friendlyName ?? ''),
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        castState.activeDevice?.friendlyName ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.greenAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            castState.isPlaying ? '正在播放' : '已连接',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 播放控制
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => ref.read(castProvider.notifier).previous(),
                icon: const Icon(Icons.skip_previous_rounded,
                    color: Colors.white70, size: 28),
              ),
              const SizedBox(width: 16),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: () =>
                      ref.read(castProvider.notifier).togglePlayPause(),
                  icon: Icon(
                    castState.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: () => ref.read(castProvider.notifier).next(),
                icon: const Icon(Icons.skip_next_rounded,
                    color: Colors.white70, size: 28),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 断开连接按钮
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                ref.read(castProvider.notifier).disconnect();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.cast_connected_rounded, size: 18),
              label: const Text('断开连接'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 根据设备名猜测图标
  IconData _getDeviceIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('tv') || lower.contains('电视') || lower.contains('television')) {
      return Icons.tv_rounded;
    }
    if (lower.contains('speaker') || lower.contains('音箱') || lower.contains('homepod')) {
      return Icons.speaker_rounded;
    }
    if (lower.contains('soundbar') || lower.contains('回音壁')) {
      return Icons.surround_sound_rounded;
    }
    return Icons.devices_other_rounded;
  }
}

/// 显示投放面板的便捷方法
void showCastSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const CastSheet(),
  );
}
