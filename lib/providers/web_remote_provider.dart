import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/services/web_remote.dart';

/// Web 遥控服务状态
class WebRemoteState {
  final bool isRunning;
  final String? url;
  final int clientCount;

  const WebRemoteState({
    this.isRunning = false,
    this.url,
    this.clientCount = 0,
  });

  WebRemoteState copyWith({
    bool? isRunning,
    String? url,
    int? clientCount,
    bool clearUrl = false,
  }) {
    return WebRemoteState(
      isRunning: isRunning ?? this.isRunning,
      url: clearUrl ? null : (url ?? this.url),
      clientCount: clientCount ?? this.clientCount,
    );
  }
}

/// Web 遥控服务 Provider
final webRemoteProvider =
    NotifierProvider<WebRemoteNotifier, WebRemoteState>(WebRemoteNotifier.new);

class WebRemoteNotifier extends Notifier<WebRemoteState> {
  WebRemoteServer? _server;
  Timer? _broadcastTimer;

  @override
  WebRemoteState build() {
    ref.onDispose(() {
      _broadcastTimer?.cancel();
      _server?.stop();
    });
    return const WebRemoteState();
  }

  /// 启动 Web 遥控服务
  Future<void> start() async {
    if (_server != null) return;

    _server = WebRemoteServer(
      onCommand: _handleCommand,
    );

    try {
      final url = await _server!.start();
      state = state.copyWith(isRunning: true, url: url);

      // 定时广播播放状态（每 500ms）
      _broadcastTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _broadcastState(),
      );

      // 首次立即广播
      _broadcastState();
    } catch (e) {
      _server = null;
      rethrow;
    }
  }

  /// 停止 Web 遥控服务
  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    await _server?.stop();
    _server = null;
    state = const WebRemoteState();
  }

  /// 切换开关
  Future<void> toggle() async {
    if (state.isRunning) {
      await stop();
    } else {
      await start();
    }
  }

  /// 处理来自 Web 客户端的命令
  void _handleCommand(String cmd, Map<String, dynamic> payload) {
    final player = ref.read(playerProvider.notifier);
    final playerState = ref.read(playerProvider);

    switch (cmd) {
      case 'toggle':
        player.togglePlayPause();
        break;
      case 'next':
        player.next();
        break;
      case 'prev':
        player.previous();
        break;
      case 'volume':
        final vol = (payload['value'] as num?)?.toDouble() ?? 0.8;
        player.setVolume(vol.clamp(0.0, 1.0));
        break;
      case 'seek':
        final ratio = (payload['value'] as num?)?.toDouble() ?? 0.0;
        final duration = playerState.duration;
        if (duration.inMilliseconds > 0) {
          final newPos = Duration(
            milliseconds: (ratio * duration.inMilliseconds).toInt(),
          );
          player.seekTo(newPos);
        }
        break;
      case 'play_index':
        final idx = (payload['value'] as num?)?.toInt() ?? 0;
        player.playSongAt(idx);
        break;
      case 'get_state':
        // 立即推送当前状态
        _broadcastState();
        break;
    }
  }

  /// 广播当前播放状态给所有 Web 客户端
  void _broadcastState() {
    if (_server == null || !_server!.isRunning) return;

    final ps = ref.read(playerProvider);
    final stateMap = <String, dynamic>{
      'title': ps.currentSong?.title ?? '',
      'artist': ps.currentSong?.artist ?? '',
      'isPlaying': ps.isPlaying,
      'position': ps.position.inMilliseconds,
      'duration': ps.duration.inMilliseconds,
      'volume': ps.volume,
      'currentIndex': ps.currentIndex,
      'playlist': ps.playlist
          .map((s) => {
                'title': s.title,
                'artist': s.artist,
              })
          .toList(),
    };

    _server!.broadcast(stateMap);

    // 更新客户端计数
    final count = _server!.clientCount;
    if (count != state.clientCount) {
      state = state.copyWith(clientCount: count);
    }
  }
}
