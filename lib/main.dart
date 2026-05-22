import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:jmusic/src/rust/frb_generated.dart';
import 'package:jmusic/src/rust/api/simple.dart' as rust_simple;
import 'package:jmusic/pages/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await RustLib.init();
  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Rust 初始化失败: $e')),
      ),
    ));
    return;
  }

  // 设置应用数据目录（Android 上需要传入正确的路径）
  try {
    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = '${appDir.path}/.jmusic';
    await Directory(dataDir).create(recursive: true);
    rust_simple.setAppDataDir(path: dataDir);
  } catch (_) {}

  runApp(const ProviderScope(child: JMusicApp()));
}

class JMusicApp extends StatelessWidget {
  const JMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JMusic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'System',
        // 深色主题背景
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardTheme: const CardThemeData(color: Color(0xFF1E1E2E), elevation: 0),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      home: const HomePage(),
    );
  }
}
