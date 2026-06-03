import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/providers/webdav_provider.dart';
import 'package:jmusic/services/dlna_service.dart';
import 'package:jmusic/services/media_stream_server.dart';
import 'package:jmusic/src/rust/models/song.dart';

/// 投放连接状态
enum CastConnectionState {
  /// 未连接
  disconnected,

  /// 正在连接
  connecting,

  /// 已连接
  connected,

  /// 连接失败
  error,
}

/// 投放状态
class CastState {
  final CastConnectionState connectionState;
  final List<DlnaDevice> devices;
  final DlnaDevice? activeDevice;
  final bool isDiscovering;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final String? error;

  const CastState({
    this.connectionState = CastConnectionState.disconnected,
    this.devices = const [],
    this.activeDevice,
    this.isDiscovering = false,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.error,
  });

  bool get isCasting =>
      connectionState == CastConnectionState.connected &&
      activeDevice != null;

  CastState copyWith({
    CastConnectionState? connectionState,
    List<DlnaDevice>? devices,
    DlnaDevice? activeDevice,
    bool? isDiscovering,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    String? error,
    bool clearDevice = false,
    bool clearError = false,
  }) {
    return CastState(
      connectionState: connectionState ?? this.connectionState,
      devices: devices ?? this.devices,
      activeDevice: clearDevice ? null : (activeDevice ?? this.activeDevice),
      isDiscovering: isDiscovering ?? this.isDiscovering,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 投放服务 Provider
final castProvider =
    NotifierProvider<CastNotifier, CastState>(CastNotifier.new);

class CastNotifier extends Notifier<CastState> {
  final DlnaService _dlnaService = DlnaService();
  final MediaStreamServer _mediaServer = MediaStreamServer();
  StreamSubscription<List<DlnaDevice>>? _devicesSub;
  Timer? _positionTimer;

  @override
  CastState build() {
    ref.onDispose(() {
      _devicesSub?.cancel();
      _positionTimer?.cancel();
      _dlnaService.dispose();
      _mediaServer.stop();
    });
    return const CastState();
  }

  /// 开始扫描 DLNA 设备
  Future<void> startDiscovery() async {
    state = state.copyWith(isDiscovering: true, devices: []);

    _devicesSub?.cancel();
    _devicesSub = _dlnaService.devicesStream.listen((devices) {
      state = state.copyWith(devices: devices);
    });

    await _dlnaService.startDiscovery();
  }

  /// 停止扫描
  Future<void> stopDiscovery() async {
    await _dlnaService.stopDiscovery();
    _devicesSub?.cancel();
    _devicesSub = null;
    state = state.copyWith(isDiscovering: false);
  }

  /// 连接到指定设备
  Future<void> connectToDevice(DlnaDevice device) async {
    state = state.copyWith(
      connectionState: CastConnectionState.connecting,
      activeDevice: device,
      clearError: true,
    );

    try {
      // 确保媒体流服务器已启动
      if (!_mediaServer.isRunning) {
        await _mediaServer.start();
      }

      // 测试设备连通性（获取传输状态）
      final transportState = await _dlnaService.getTransportState(device);
      if (transportState == DlnaTransportState.unknown) {
        // 再试一次
        await Future.delayed(const Duration(milliseconds: 500));
        final retryState = await _dlnaService.getTransportState(device);
        if (retryState == DlnaTransportState.unknown) {
          state = state.copyWith(
            connectionState: CastConnectionState.error,
            error: '无法连接到设备',
          );
          return;
        }
      }

      state = state.copyWith(
        connectionState: CastConnectionState.connected,
      );

      // 停止发现（已连接）
      await stopDiscovery();

      // 如果当前有正在播放的歌曲，自动推送
      final playerState = ref.read(playerProvider);
      if (playerState.currentSong != null && playerState.isPlaying) {
        await castCurrentSong();
      }

      debugPrint('[Cast] 已连接到: ${device.friendlyName}');
    } catch (e) {
      state = state.copyWith(
        connectionState: CastConnectionState.error,
        error: '连接失败: $e',
      );
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    if (state.activeDevice != null) {
      try {
        await _dlnaService.stop(state.activeDevice!);
      } catch (_) {}
    }

    _positionTimer?.cancel();
    _positionTimer = null;

    state = state.copyWith(
      connectionState: CastConnectionState.disconnected,
      clearDevice: true,
      isPlaying: false,
      position: Duration.zero,
      duration: Duration.zero,
    );

    debugPrint('[Cast] 已断开连接');
  }

  /// 投放当前正在播放的歌曲
  Future<void> castCurrentSong() async {
    if (!state.isCasting) return;

    final playerState = ref.read(playerProvider);
    final song = playerState.currentSong;
    if (song == null) return;

    await _castSong(song);
  }

  /// 投放指定歌曲
  Future<void> _castSong(Song song) async {
    if (!state.isCasting) return;

    final device = state.activeDevice!;

    // 获取本地文件路径（WebDAV 文件需要先缓存）
    String filePath = song.filePath;
    if (filePath.startsWith('webdav://')) {
      final webDav = ref.read(webDavProvider.notifier);
      filePath = await webDav.ensureLocalFile(song);
    }

    // 通过媒体服务器暴露文件
    final streamUrl = _mediaServer.serveFile(filePath);
    if (streamUrl == null) {
      state = state.copyWith(error: '无法创建媒体流');
      return;
    }

    // 推送到 DLNA 设备
    final setResult = await _dlnaService.setAVTransportURI(
      device,
      streamUrl,
      title: song.title,
      artist: song.artist,
    );

    if (!setResult) {
      state = state.copyWith(error: '推送媒体到设备失败');
      return;
    }

    // 播放
    final playResult = await _dlnaService.play(device);
    if (!playResult) {
      state = state.copyWith(error: '设备播放失败');
      return;
    }

    state = state.copyWith(
      isPlaying: true,
      position: Duration.zero,
      duration: Duration(seconds: song.duration.toInt()),
      clearError: true,
    );

    // 启动进度轮询
    _startPositionPolling();

    debugPrint('[Cast] 正在投放: ${song.title}');
  }

  /// 投放时的播放/暂停切换
  Future<void> togglePlayPause() async {
    if (!state.isCasting) return;
    final device = state.activeDevice!;

    if (state.isPlaying) {
      final success = await _dlnaService.pause(device);
      if (success) {
        state = state.copyWith(isPlaying: false);
      }
    } else {
      final success = await _dlnaService.play(device);
      if (success) {
        state = state.copyWith(isPlaying: true);
      }
    }
  }

  /// 投放时 seek
  Future<void> seekTo(Duration position) async {
    if (!state.isCasting) return;
    final device = state.activeDevice!;

    final success = await _dlnaService.seek(device, position);
    if (success) {
      state = state.copyWith(position: position);
    }
  }

  /// 投放时设置音量
  Future<void> setVolume(double volume) async {
    if (!state.isCasting) return;
    final device = state.activeDevice!;

    await _dlnaService.setVolume(device, (volume * 100).toInt());
  }

  /// 投放下一首
  Future<void> next() async {
    if (!state.isCasting) return;

    // 让 playerProvider 切歌，然后投放新歌
    ref.read(playerProvider.notifier).next();

    // 等待切歌完成
    await Future.delayed(const Duration(milliseconds: 300));
    await castCurrentSong();
  }

  /// 投放上一首
  Future<void> previous() async {
    if (!state.isCasting) return;

    ref.read(playerProvider.notifier).previous();

    await Future.delayed(const Duration(milliseconds: 300));
    await castCurrentSong();
  }

  /// 投放时停止
  Future<void> stopCasting() async {
    if (!state.isCasting) return;
    final device = state.activeDevice!;

    await _dlnaService.stop(device);
    _positionTimer?.cancel();
    state = state.copyWith(
      isPlaying: false,
      position: Duration.zero,
    );
  }

  /// 定期轮询投放设备的播放进度
  void _startPositionPolling() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!state.isCasting) return;

      try {
        final info = await _dlnaService.getPositionInfo(state.activeDevice!);
        if (info != null) {
          state = state.copyWith(
            position: info['position'] as Duration,
            duration: info['duration'] as Duration,
          );
        }

        // 检查是否播放结束
        final transport =
            await _dlnaService.getTransportState(state.activeDevice!);
        if (transport == DlnaTransportState.stopped && state.isPlaying) {
          // 播放结束，自动下一首
          await next();
        }
      } catch (e) {
        debugPrint('[Cast] 轮询进度错误: $e');
      }
    });
  }
}
