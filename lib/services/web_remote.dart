import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'web_remote_html.dart';

/// Web 遥控服务器 — 提供 HTTP 静态页面 + WebSocket 双向通信
class WebRemoteServer {
  static const int defaultPort = 9621;

  HttpServer? _server;
  final Set<WebSocket> _clients = {};
  final void Function(String command, Map<String, dynamic> payload)? onCommand;

  /// 当前服务器是否运行中
  bool get isRunning => _server != null;

  /// 当前监听地址（供 QR 码使用）
  String? get url => _url;
  String? _url;

  WebRemoteServer({this.onCommand});

  /// 启动服务器
  Future<String> start({int port = defaultPort}) async {
    if (_server != null) {
      return _url!;
    }

    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    debugPrint('[WebRemote] 服务器启动: http://0.0.0.0:$port');

    _server!.listen(_handleRequest);

    // 获取局域网 IP
    final ip = await _getLanIp();
    _url = 'http://$ip:$port';
    return _url!;
  }

  /// 停止服务器
  Future<void> stop() async {
    for (final client in _clients) {
      await client.close(WebSocketStatus.goingAway, '服务器关闭');
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    _url = null;
    debugPrint('[WebRemote] 服务器已停止');
  }

  /// 向所有客户端广播状态
  void broadcast(Map<String, dynamic> state) {
    final msg = jsonEncode(state);
    final disconnected = <WebSocket>[];
    for (final client in _clients) {
      try {
        client.add(msg);
      } catch (_) {
        disconnected.add(client);
      }
    }
    for (final c in disconnected) {
      _clients.remove(c);
    }
  }

  /// 获取连接的客户端数量
  int get clientCount => _clients.length;

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    // WebSocket 升级
    if (path == '/ws') {
      try {
        final ws = await WebSocketTransformer.upgrade(request);
        _clients.add(ws);
        debugPrint('[WebRemote] 客户端连接 (${_clients.length} 在线)');

        ws.listen(
          (data) {
            try {
              final msg = jsonDecode(data as String) as Map<String, dynamic>;
              final cmd = msg['cmd'] as String? ?? '';
              onCommand?.call(cmd, msg);
            } catch (e) {
              debugPrint('[WebRemote] 解析消息失败: $e');
            }
          },
          onDone: () {
            _clients.remove(ws);
            debugPrint('[WebRemote] 客户端断开 (${_clients.length} 在线)');
          },
          onError: (_) {
            _clients.remove(ws);
          },
        );
      } catch (e) {
        debugPrint('[WebRemote] WebSocket 升级失败: $e');
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..close();
      }
      return;
    }

    // 静态页面
    if (path == '/' || path == '/index.html') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(remoteControlHtml)
        ..close();
      return;
    }

    // 404
    request.response
      ..statusCode = HttpStatus.notFound
      ..write('Not Found')
      ..close();
  }

  /// 获取本机局域网 IP
  static Future<String> _getLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address.startsWith('192.168.') ||
              addr.address.startsWith('10.') ||
              addr.address.startsWith('172.')) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }
}
