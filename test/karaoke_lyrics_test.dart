import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmusic/src/rust/models/lyrics.dart';
import 'package:jmusic/widgets/karaoke_lyric_line.dart';

void main() {
  group('KaraokeLyricLine 渲染与降级测试', () {
    testWidgets('无逐字时间戳时优雅降级为普通 Text 渲染', (WidgetTester tester) async {
      final line = LyricLine(
        timeMs: BigInt.from(1000),
        text: '这是一行普通歌词',
        words: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KaraokeLyricLine(
              line: line,
              currentMs: 1500,
              isCurrentLine: true,
              textStyle: const TextStyle(fontSize: 16),
              activeColor: Colors.blue,
              inactiveColor: Colors.grey,
            ),
          ),
        ),
      );

      // 应直接渲染普通 Text
      expect(find.text('这是一行普通歌词'), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text('这是一行普通歌词'));
      expect(textWidget.style?.color, Colors.blue);
    });

    testWidgets('具备逐字时间戳时使用 Wrap 渲染逐字渐变', (WidgetTester tester) async {
      final line = LyricLine(
        timeMs: BigInt.from(1000),
        text: '你好呀',
        words: [
          LyricWord(text: '你', startMs: BigInt.from(1000), durationMs: BigInt.from(300)),
          LyricWord(text: '好', startMs: BigInt.from(1300), durationMs: BigInt.from(300)),
          LyricWord(text: '呀', startMs: BigInt.from(1600), durationMs: BigInt.from(300)),
        ],
      );

      // 当播放到 1150ms（"你" 正在唱中）
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KaraokeLyricLine(
              line: line,
              currentMs: 1150,
              isCurrentLine: true,
              textStyle: const TextStyle(fontSize: 16),
              activeColor: Colors.blue,
              inactiveColor: Colors.grey,
            ),
          ),
        ),
      );

      // 验证各个字都被正确构建出来
      expect(find.text('你'), findsOneWidget);
      expect(find.text('好'), findsOneWidget);
      expect(find.text('呀'), findsOneWidget);

      // 正在唱的字使用了 ShaderMask 渐变遮罩
      expect(find.byType(ShaderMask), findsOneWidget);
    });
  });
}

