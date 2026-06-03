import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// DLNA 渲染设备信息
class DlnaDevice {
  final String usn;
  final String friendlyName;
  final String location; // 设备描述 XML 的 URL
  final String controlUrl; // AVTransport 控制 URL
  final String baseUrl; // 设备 base URL
  final InternetAddress address;

  const DlnaDevice({
    required this.usn,
    required this.friendlyName,
    required this.location,
    required this.controlUrl,
    required this.baseUrl,
    required this.address,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DlnaDevice &&
          runtimeType == other.runtimeType &&
          usn == other.usn;

  @override
  int get hashCode => usn.hashCode;

  @override
  String toString() => 'DlnaDevice($friendlyName @ $baseUrl)';
}

/// DLNA 传输状态
enum DlnaTransportState {
  stopped,
  playing,
  paused,
  transitioning,
  noMediaPresent,
  unknown,
}

/// DLNA 服务 — SSDP 设备发现 + UPnP AVTransport 控制
class DlnaService {
  static const _ssdpAddress = '239.255.255.250';
  static const _ssdpPort = 1900;
  static const _searchTarget = 'urn:schemas-upnp-org:service:AVTransport:1';

  final HttpClient _httpClient = HttpClient();
  RawDatagramSocket? _ssdpSocket;
  Timer? _discoveryTimer;

  final _devicesController = StreamController<List<DlnaDevice>>.broadcast();
  final Map<String, DlnaDevice> _devices = {};

  /// 已发现的设备流
  Stream<List<DlnaDevice>> get devicesStream => _devicesController.stream;

  /// 当前已发现的设备列表
  List<DlnaDevice> get devices => _devices.values.toList();

  DlnaService() {
    _httpClient.connectionTimeout = const Duration(seconds: 5);
  }

  /// 开始 SSDP 设备发现
  Future<void> startDiscovery() async {
    await stopDiscovery();
    _devices.clear();
    _devicesController.add([]);

    try {
      _ssdpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );

      _ssdpSocket!.broadcastEnabled = true;
      _ssdpSocket!.multicastLoopback = false;

      // 尝试加入多播组
      try {
        _ssdpSocket!.joinMulticast(InternetAddress(_ssdpAddress));
      } catch (e) {
        debugPrint('[DLNA] 加入多播组失败 (非关键): $e');
      }

      _ssdpSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _ssdpSocket!.receive();
          if (datagram != null) {
            _handleSsdpResponse(
              utf8.decode(datagram.data),
              datagram.address,
            );
          }
        }
      });

      // 发送 M-SEARCH 请求
      _sendMSearch();

      // 定期重新发送搜索
      _discoveryTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _sendMSearch(),
      );
    } catch (e) {
      debugPrint('[DLNA] startDiscovery 失败: $e');
    }
  }

  /// 停止设备发现
  Future<void> stopDiscovery() async {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    _ssdpSocket?.close();
    _ssdpSocket = null;
  }

  /// 发送 SSDP M-SEARCH 请求
  void _sendMSearch() {
    if (_ssdpSocket == null) return;

    final request = 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $_ssdpAddress:$_ssdpPort\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 3\r\n'
        'ST: $_searchTarget\r\n'
        '\r\n';

    try {
      _ssdpSocket!.send(
        utf8.encode(request),
        InternetAddress(_ssdpAddress),
        _ssdpPort,
      );
      debugPrint('[DLNA] 发送 M-SEARCH');
    } catch (e) {
      debugPrint('[DLNA] 发送 M-SEARCH 失败: $e');
    }
  }

  /// 处理 SSDP 响应
  void _handleSsdpResponse(String response, InternetAddress address) async {
    // 只处理 AVTransport 相关的响应
    if (!response.contains('AVTransport') &&
        !response.contains('MediaRenderer')) {
      return;
    }

    // 提取 LOCATION 和 USN
    final locationMatch = RegExp(
      r'LOCATION:\s*(.+?)[\r\n]',
      caseSensitive: false,
    ).firstMatch(response);
    final usnMatch = RegExp(
      r'USN:\s*(.+?)[\r\n]',
      caseSensitive: false,
    ).firstMatch(response);

    if (locationMatch == null) return;

    final location = locationMatch.group(1)!.trim();
    final usn = usnMatch?.group(1)?.trim() ?? location;

    // 去重
    if (_devices.containsKey(usn)) return;

    // 获取设备描述以得到友好名称和控制 URL
    try {
      final device = await _fetchDeviceInfo(location, usn, address);
      if (device != null) {
        _devices[usn] = device;
        _devicesController.add(_devices.values.toList());
        debugPrint('[DLNA] 发现设备: ${device.friendlyName}');
      }
    } catch (e) {
      debugPrint('[DLNA] 获取设备信息失败: $e');
    }
  }

  /// 获取设备详细信息（解析设备描述 XML）
  Future<DlnaDevice?> _fetchDeviceInfo(
    String location,
    String usn,
    InternetAddress address,
  ) async {
    try {
      final uri = Uri.parse(location);
      final request = await _httpClient.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) return null;

      final xml = await response.transform(utf8.decoder).join();

      // 提取 friendlyName
      final nameMatch = RegExp(
        r'<friendlyName>(.*?)</friendlyName>',
      ).firstMatch(xml);
      final friendlyName = nameMatch?.group(1) ?? '未知设备';

      // 提取 AVTransport controlURL
      final controlUrl = _extractControlUrl(xml, location);
      if (controlUrl == null) return null;

      final baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';

      return DlnaDevice(
        usn: usn,
        friendlyName: friendlyName,
        location: location,
        controlUrl: controlUrl,
        baseUrl: baseUrl,
        address: address,
      );
    } catch (e) {
      debugPrint('[DLNA] _fetchDeviceInfo 错误: $e');
      return null;
    }
  }

  /// 从设备描述 XML 中提取 AVTransport 的 controlURL
  String? _extractControlUrl(String xml, String location) {
    final uri = Uri.parse(location);
    final baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';

    // 查找包含 AVTransport 的 service 块并提取 controlURL
    final serviceRegex = RegExp(
      r'<service>.*?AVTransport.*?<controlURL>(.*?)</controlURL>.*?</service>',
      dotAll: true,
    );
    final match = serviceRegex.firstMatch(xml);

    if (match != null) {
      final controlPath = match.group(1)!.trim();
      if (controlPath.startsWith('http')) {
        return controlPath;
      }
      return '$baseUrl$controlPath';
    }

    // 备选：逐个 service 块搜索
    final serviceBlocks = RegExp(
      r'<service>(.*?)</service>',
      dotAll: true,
    ).allMatches(xml);

    for (final block in serviceBlocks) {
      final content = block.group(1) ?? '';
      if (content.contains('AVTransport')) {
        final ctrlMatch = RegExp(
          r'<controlURL>(.*?)</controlURL>',
        ).firstMatch(content);
        if (ctrlMatch != null) {
          final controlPath = ctrlMatch.group(1)!.trim();
          if (controlPath.startsWith('http')) {
            return controlPath;
          }
          return '$baseUrl$controlPath';
        }
      }
    }

    return null;
  }

  // ─── AVTransport SOAP 控制 ────────────────────────────────────────────

  /// 设置播放 URI（推送音乐到设备）
  Future<bool> setAVTransportURI(
    DlnaDevice device,
    String mediaUrl, {
    String title = '',
    String artist = '',
  }) async {
    final metadata = _buildDidlMetadata(mediaUrl, title, artist);
    final body = _soapEnvelope('SetAVTransportURI', {
      'InstanceID': '0',
      'CurrentURI': _xmlEscape(mediaUrl),
      'CurrentURIMetaData': _xmlEscape(metadata),
    });

    return await _sendSoapAction(device, 'SetAVTransportURI', body);
  }

  /// 播放
  Future<bool> play(DlnaDevice device, {String speed = '1'}) async {
    final body = _soapEnvelope('Play', {
      'InstanceID': '0',
      'Speed': speed,
    });
    return await _sendSoapAction(device, 'Play', body);
  }

  /// 暂停
  Future<bool> pause(DlnaDevice device) async {
    final body = _soapEnvelope('Pause', {
      'InstanceID': '0',
    });
    return await _sendSoapAction(device, 'Pause', body);
  }

  /// 停止
  Future<bool> stop(DlnaDevice device) async {
    final body = _soapEnvelope('Stop', {
      'InstanceID': '0',
    });
    return await _sendSoapAction(device, 'Stop', body);
  }

  /// 跳转到指定位置
  Future<bool> seek(DlnaDevice device, Duration position) async {
    final timeStr = _durationToString(position);
    final body = _soapEnvelope('Seek', {
      'InstanceID': '0',
      'Unit': 'REL_TIME',
      'Target': timeStr,
    });
    return await _sendSoapAction(device, 'Seek', body);
  }

  /// 获取当前传输状态和进度
  Future<Map<String, dynamic>?> getPositionInfo(DlnaDevice device) async {
    final body = _soapEnvelope('GetPositionInfo', {
      'InstanceID': '0',
    });

    try {
      final response = await _sendSoapRequest(device, 'GetPositionInfo', body);
      if (response == null) return null;

      final trackDuration = _parseTimeString(
        _extractXmlValue(response, 'TrackDuration') ?? '0:00:00',
      );
      final relTime = _parseTimeString(
        _extractXmlValue(response, 'RelTime') ?? '0:00:00',
      );

      return {
        'duration': trackDuration,
        'position': relTime,
        'trackURI': _extractXmlValue(response, 'TrackURI') ?? '',
      };
    } catch (e) {
      debugPrint('[DLNA] getPositionInfo 错误: $e');
      return null;
    }
  }

  /// 获取传输状态
  Future<DlnaTransportState> getTransportState(DlnaDevice device) async {
    final body = _soapEnvelope('GetTransportInfo', {
      'InstanceID': '0',
    });

    try {
      final response = await _sendSoapRequest(device, 'GetTransportInfo', body);
      if (response == null) return DlnaTransportState.unknown;

      final stateStr =
          _extractXmlValue(response, 'CurrentTransportState') ?? '';
      return _parseTransportState(stateStr);
    } catch (e) {
      return DlnaTransportState.unknown;
    }
  }

  /// 设置音量（RenderingControl 服务）
  Future<bool> setVolume(DlnaDevice device, int volume) async {
    // 需要使用 RenderingControl 的 controlURL，此处简化处理
    // 大多数设备的 RenderingControl URL 与 AVTransport 同级
    final controlUrl =
        device.controlUrl.replaceAll('AVTransport', 'RenderingControl');

    final body = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:SetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
      <InstanceID>0</InstanceID>
      <Channel>Master</Channel>
      <DesiredVolume>${volume.clamp(0, 100)}</DesiredVolume>
    </u:SetVolume>
  </s:Body>
</s:Envelope>''';

    try {
      final uri = Uri.parse(controlUrl);
      final request = await _httpClient.postUrl(uri);
      request.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      request.headers.set(
        'SOAPAction',
        '"urn:schemas-upnp-org:service:RenderingControl:1#SetVolume"',
      );
      request.write(body);

      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[DLNA] setVolume 失败: $e');
      return false;
    }
  }

  // ─── SOAP 辅助方法 ────────────────────────────────────────────────────

  /// 构造 SOAP 信封
  String _soapEnvelope(String action, Map<String, String> args) {
    final argsXml = args.entries
        .map((e) => '      <${e.key}>${e.value}</${e.key}>')
        .join('\n');

    return '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:$action xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
$argsXml
    </u:$action>
  </s:Body>
</s:Envelope>''';
  }

  /// 发送 SOAP 请求并检查状态码
  Future<bool> _sendSoapAction(
    DlnaDevice device,
    String action,
    String body,
  ) async {
    try {
      final uri = Uri.parse(device.controlUrl);
      final request = await _httpClient.postUrl(uri);
      request.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      request.headers.set(
        'SOAPAction',
        '"urn:schemas-upnp-org:service:AVTransport:1#$action"',
      );
      request.write(body);

      final response = await request.close();
      await response.drain();
      final success = response.statusCode == 200;
      if (!success) {
        debugPrint('[DLNA] $action 失败: HTTP ${response.statusCode}');
      }
      return success;
    } catch (e) {
      debugPrint('[DLNA] $action 错误: $e');
      return false;
    }
  }

  /// 发送 SOAP 请求并返回响应 body
  Future<String?> _sendSoapRequest(
    DlnaDevice device,
    String action,
    String body,
  ) async {
    try {
      final uri = Uri.parse(device.controlUrl);
      final request = await _httpClient.postUrl(uri);
      request.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      request.headers.set(
        'SOAPAction',
        '"urn:schemas-upnp-org:service:AVTransport:1#$action"',
      );
      request.write(body);

      final response = await request.close();
      if (response.statusCode != 200) return null;
      return await response.transform(utf8.decoder).join();
    } catch (e) {
      debugPrint('[DLNA] $action 请求错误: $e');
      return null;
    }
  }

  /// 构建 DIDL-Lite 元数据
  String _buildDidlMetadata(String url, String title, String artist) {
    return '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="-1" restricted="1">'
        '<dc:title>${_xmlEscape(title)}</dc:title>'
        '<dc:creator>${_xmlEscape(artist)}</dc:creator>'
        '<upnp:class>object.item.audioItem.musicTrack</upnp:class>'
        '<res protocolInfo="http-get:*:audio/mpeg:*">$url</res>'
        '</item>'
        '</DIDL-Lite>';
  }

  /// XML 特殊字符转义
  String _xmlEscape(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Duration 转为 H:MM:SS 格式
  String _durationToString(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 解析 H:MM:SS 时间字符串
  Duration _parseTimeString(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length == 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final seconds = double.parse(parts[2]);
        return Duration(
          hours: hours,
          minutes: minutes,
          seconds: seconds.toInt(),
          milliseconds: ((seconds % 1) * 1000).toInt(),
        );
      }
    } catch (_) {}
    return Duration.zero;
  }

  /// 从 XML 中提取值
  String? _extractXmlValue(String xml, String tag) {
    final match = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml);
    return match?.group(1);
  }

  /// 解析传输状态字符串
  DlnaTransportState _parseTransportState(String stateStr) {
    switch (stateStr.toUpperCase()) {
      case 'STOPPED':
        return DlnaTransportState.stopped;
      case 'PLAYING':
        return DlnaTransportState.playing;
      case 'PAUSED_PLAYBACK':
      case 'PAUSED':
        return DlnaTransportState.paused;
      case 'TRANSITIONING':
        return DlnaTransportState.transitioning;
      case 'NO_MEDIA_PRESENT':
        return DlnaTransportState.noMediaPresent;
      default:
        return DlnaTransportState.unknown;
    }
  }

  /// 释放资源
  void dispose() {
    stopDiscovery();
    _devicesController.close();
    _httpClient.close();
  }
}
