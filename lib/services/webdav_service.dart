import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WebDAV 连接配置
class WebDavConfig {
  final String url; // 如 https://dav.jianguoyun.com/dav/Music
  final String username;
  final String password;
  final String name; // 用户自定义名称

  const WebDavConfig({
    required this.url,
    required this.username,
    required this.password,
    this.name = 'WebDAV',
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'username': username,
        'password': password,
        'name': name,
      };

  factory WebDavConfig.fromJson(Map<String, dynamic> json) => WebDavConfig(
        url: json['url'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        name: json['name'] as String? ?? 'WebDAV',
      );

  /// Basic Auth header
  String get authHeader =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  /// 标准化 URL（确保末尾有 /）
  String get normalizedUrl => url.endsWith('/') ? url : '$url/';
}

/// WebDAV 远程文件信息
class WebDavFile {
  final String href; // 相对路径
  final String name; // 文件名
  final int contentLength;
  final bool isDirectory;

  const WebDavFile({
    required this.href,
    required this.name,
    required this.contentLength,
    required this.isDirectory,
  });
}

/// WebDAV 服务 — 列出文件、下载缓存
class WebDavService {
  static const _kConfigPrefKey = 'webdav_configs';
  static const _supportedExtensions = {
    'mp3', 'flac', 'wav', 'ogg', 'm4a', 'aac', 'wma', 'ape'
  };

  final HttpClient _client = HttpClient();

  WebDavService() {
    _client.connectionTimeout = const Duration(seconds: 10);
  }

  /// 测试连接
  Future<bool> testConnection(WebDavConfig config) async {
    try {
      final files = await listFiles(config, '/');
      return files != null;
    } catch (_) {
      return false;
    }
  }

  /// 列出目录下的文件（PROPFIND）
  Future<List<WebDavFile>?> listFiles(
      WebDavConfig config, String path) async {
    try {
      final uri = Uri.parse('${config.normalizedUrl}${_trimSlash(path)}');
      final request = await _client.openUrl('PROPFIND', uri);
      request.headers.set('Authorization', config.authHeader);
      request.headers.set('Depth', '1');
      request.headers.set('Content-Type', 'application/xml; charset=utf-8');
      request.write('''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:getcontentlength/>
    <d:resourcetype/>
  </d:prop>
</d:propfind>''');

      final response = await request.close();
      if (response.statusCode != 207) {
        debugPrint('[WebDAV] PROPFIND 失败: ${response.statusCode}');
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      return _parseMultiStatus(body, path);
    } catch (e) {
      debugPrint('[WebDAV] listFiles 错误: $e');
      return null;
    }
  }

  /// 递归列出所有音频文件
  Future<List<WebDavFile>> listAllAudioFiles(
      WebDavConfig config, String basePath) async {
    final result = <WebDavFile>[];
    final files = await listFiles(config, basePath);
    if (files == null) return result;

    for (final file in files) {
      if (file.isDirectory) {
        // 递归子目录
        final subFiles = await listAllAudioFiles(config, file.href);
        result.addAll(subFiles);
      } else {
        // 检查是否为音频文件
        final ext = file.name.split('.').last.toLowerCase();
        if (_supportedExtensions.contains(ext)) {
          result.add(file);
        }
      }
    }
    return result;
  }

  /// 下载文件到本地缓存，返回本地路径
  Future<String> downloadToCache(
      WebDavConfig config, String remotePath,
      {void Function(double progress)? onProgress}) async {
    final cacheDir = await _getCacheDir();
    // 用 remotePath 的 hash 作为缓存文件名，保留扩展名
    final ext = remotePath.split('.').last.toLowerCase();
    final hash = remotePath.hashCode.toRadixString(16);
    final localPath = '${cacheDir.path}/$hash.$ext';

    final localFile = File(localPath);
    if (await localFile.exists()) {
      // 已缓存
      return localPath;
    }

    // 下载
    final uri = Uri.parse('${config.normalizedUrl}${_trimSlash(remotePath)}');
    final request = await _client.getUrl(uri);
    request.headers.set('Authorization', config.authHeader);

    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('下载失败: HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength;
    int receivedBytes = 0;
    final sink = localFile.openWrite();

    await for (final chunk in response) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      if (onProgress != null && totalBytes > 0) {
        onProgress(receivedBytes / totalBytes);
      }
    }
    await sink.close();

    return localPath;
  }

  /// 获取缓存目录
  Future<Directory> _getCacheDir() async {
    final appDir = await getApplicationCacheDirectory();
    final cacheDir = Directory('${appDir.path}/webdav_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// 清理缓存
  Future<void> clearCache() async {
    final cacheDir = await _getCacheDir();
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
  }

  /// 获取缓存大小（字节）
  Future<int> getCacheSize() async {
    final cacheDir = await _getCacheDir();
    if (!await cacheDir.exists()) return 0;
    int size = 0;
    await for (final entity in cacheDir.list(recursive: true)) {
      if (entity is File) {
        size += await entity.length();
      }
    }
    return size;
  }

  // ─── 持久化配置 ─────────────────────────────────────────────────────

  /// 保存配置列表
  static Future<void> saveConfigs(List<WebDavConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    final json = configs.map((c) => jsonEncode(c.toJson())).toList();
    await prefs.setStringList(_kConfigPrefKey, json);
  }

  /// 读取配置列表
  static Future<List<WebDavConfig>> loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kConfigPrefKey);
    if (list == null) return [];
    return list
        .map((s) => WebDavConfig.fromJson(
            jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  // ─── XML 解析 ─────────────────────────────────────────────────────────

  String _trimSlash(String path) {
    if (path.startsWith('/')) return path.substring(1);
    return path;
  }

  /// 简易解析 PROPFIND 207 Multi-Status 响应
  List<WebDavFile> _parseMultiStatus(String xml, String basePath) {
    final results = <WebDavFile>[];

    // 简单正则解析（避免引入 XML 库）
    final responseRegex =
        RegExp(r'<d:response>(.*?)</d:response>', dotAll: true);
    final hrefRegex = RegExp(r'<d:href>(.*?)</d:href>');
    final nameRegex = RegExp(r'<d:displayname>(.*?)</d:displayname>');
    final lengthRegex =
        RegExp(r'<d:getcontentlength>(.*?)</d:getcontentlength>');
    final collectionRegex = RegExp(r'<d:collection\s*/?>');

    for (final match in responseRegex.allMatches(xml)) {
      final block = match.group(1) ?? '';

      final href = hrefRegex.firstMatch(block)?.group(1) ?? '';
      final displayName = nameRegex.firstMatch(block)?.group(1) ?? '';
      final lengthStr = lengthRegex.firstMatch(block)?.group(1) ?? '0';
      final isDir = collectionRegex.hasMatch(block);

      // 跳过当前目录自身
      final decodedHref = Uri.decodeFull(href);
      final decodedBase = Uri.decodeFull(basePath);
      if (decodedHref == decodedBase ||
          decodedHref == '${decodedBase}/' ||
          decodedHref.endsWith('/') &&
              decodedHref.substring(0, decodedHref.length - 1) ==
                  decodedBase) {
        continue;
      }

      final name = displayName.isNotEmpty
          ? displayName
          : Uri.decodeFull(href.split('/').where((s) => s.isNotEmpty).last);

      results.add(WebDavFile(
        href: decodedHref,
        name: name,
        contentLength: int.tryParse(lengthStr) ?? 0,
        isDirectory: isDir,
      ));
    }

    return results;
  }
}
