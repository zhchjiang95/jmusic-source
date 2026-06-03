import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 本地媒体流服务器 — 为 DLNA 设备提供 HTTP 音频流
///
/// DLNA 渲染器通过 HTTP GET 请求来获取音频数据，
/// 此服务器将本地文件通过 HTTP 暴露给局域网内的 DLNA 设备。
class MediaStreamServer {
  static const int defaultPort = 9622;

  HttpServer? _server;
  String? _currentFilePath;
  String? _url;
  String? _lanIp;

  /// 服务器是否运行中
  bool get isRunning => _server != null;

  /// 当前流媒体 URL
  String? get currentStreamUrl => _url;

  /// 启动流媒体服务器
  Future<void> start({int port = defaultPort}) async {
    if (_server != null) return;

    _lanIp = await _getLanIp();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    debugPrint('[MediaStream] 服务器启动: http://$_lanIp:$port');

    _server!.listen(_handleRequest);
  }

  /// 停止服务器
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _url = null;
    _currentFilePath = null;
    debugPrint('[MediaStream] 服务器已停止');
  }

  /// 设置当前要推流的文件，返回可访问的 HTTP URL
  String? serveFile(String filePath) {
    if (_server == null || _lanIp == null) return null;

    _currentFilePath = filePath;

    // 获取文件扩展名来设置 MIME
    final fileName = Uri.encodeComponent(
      filePath.split(Platform.pathSeparator).last,
    );

    _url = 'http://$_lanIp:${_server!.port}/stream/$fileName';
    debugPrint('[MediaStream] 提供文件: $_url');
    return _url;
  }

  /// 处理 HTTP 请求
  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    if (path.startsWith('/stream/') && _currentFilePath != null) {
      await _serveAudioFile(request);
      return;
    }

    // 健康检查
    if (path == '/health') {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('OK')
        ..close();
      return;
    }

    request.response
      ..statusCode = HttpStatus.notFound
      ..write('Not Found')
      ..close();
  }

  /// 提供音频文件（支持 Range 请求以兼容更多 DLNA 设备）
  Future<void> _serveAudioFile(HttpRequest request) async {
    final file = File(_currentFilePath!);

    if (!await file.exists()) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('File not found')
        ..close();
      return;
    }

    final fileLength = await file.length();
    final mimeType = _getMimeType(_currentFilePath!);

    // 处理 Range 请求（DLNA 设备常用）
    final rangeHeader = request.headers.value('range');

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      await _serveRangeRequest(request, file, fileLength, mimeType, rangeHeader);
    } else {
      // 完整文件响应
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.parse(mimeType)
        ..headers.contentLength = fileLength
        ..headers.set('Accept-Ranges', 'bytes')
        ..headers.set('Content-Disposition', 'inline')
        ..headers.set('transferMode.dlna.org', 'Streaming')
        ..headers.set('contentFeatures.dlna.org',
            'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000');

      await file.openRead().pipe(request.response);
    }
  }

  /// 处理 Range 请求
  Future<void> _serveRangeRequest(
    HttpRequest request,
    File file,
    int fileLength,
    String mimeType,
    String rangeHeader,
  ) async {
    // 解析 Range: bytes=start-end
    final rangeStr = rangeHeader.substring(6); // 去掉 "bytes="
    final parts = rangeStr.split('-');

    int start = 0;
    int end = fileLength - 1;

    if (parts[0].isNotEmpty) {
      start = int.parse(parts[0]);
    }
    if (parts.length > 1 && parts[1].isNotEmpty) {
      end = int.parse(parts[1]);
    }

    // 确保范围有效
    if (start >= fileLength) {
      request.response
        ..statusCode = HttpStatus.requestedRangeNotSatisfiable
        ..headers.set('Content-Range', 'bytes */$fileLength')
        ..close();
      return;
    }

    end = end.clamp(start, fileLength - 1);
    final contentLength = end - start + 1;

    request.response
      ..statusCode = HttpStatus.partialContent
      ..headers.contentType = ContentType.parse(mimeType)
      ..headers.contentLength = contentLength
      ..headers.set('Accept-Ranges', 'bytes')
      ..headers.set('Content-Range', 'bytes $start-$end/$fileLength')
      ..headers.set('transferMode.dlna.org', 'Streaming')
      ..headers.set('contentFeatures.dlna.org',
          'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000');

    await file.openRead(start, end + 1).pipe(request.response);
  }

  /// 根据文件扩展名获取 MIME 类型
  String _getMimeType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp3':
        return 'audio/mpeg';
      case 'flac':
        return 'audio/flac';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'm4a':
      case 'aac':
        return 'audio/mp4';
      case 'wma':
        return 'audio/x-ms-wma';
      case 'ape':
        return 'audio/x-ape';
      default:
        return 'application/octet-stream';
    }
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
