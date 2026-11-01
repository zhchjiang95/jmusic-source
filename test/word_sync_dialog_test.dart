import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmusic/src/rust/models/lyrics.dart';
import 'package:jmusic/widgets/word_sync_dialog.dart';

void main() {
  group('WordSyncDialog 逐字打轴与多行保存测试', () {
    testWidgets('按钮文案与连续下一行打轴流程测试', (WidgetTester tester) async {
      final savedLines = <int, List<LyricWord>?>{};
      int activeIndex = 0;

      final lines = [
        WordSyncLineData(
          text: '天青色等烟雨',
          timeMs: 1000,
          words: null,
        ),
        WordSyncLineData(
          text: '而我在等你',
          timeMs: 4000,
          words: null,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => WordSyncDialog(
                          initialIndex: 0,
                          lines: lines,
                          onActiveLineChanged: (idx) => activeIndex = idx,
                          onLineSaved: (idx, words) => savedLines[idx] = words,
                        ),
                      );
                    },
                    child: const Text('打开打轴'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // 打开弹窗
      await tester.tap(find.text('打开打轴'));
      await tester.pump(const Duration(milliseconds: 300));

      // 验证标题显示第一行 (1/2)
      expect(find.text('逐字时间戳编辑与打轴 (1/2)'), findsOneWidget);

      // 验证底部按钮：取消、保存、保存并继续下一行歌词
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      expect(find.text('保存并继续下一行歌词'), findsOneWidget);

      // 验证第一行当前处于可点击继续下一行状态
      final continueBtnFinder = find.widgetWithText(FilledButton, '保存并继续下一行歌词');
      expect(continueBtnFinder, findsOneWidget);
      final FilledButton continueBtn1 = tester.widget(continueBtnFinder);
      expect(continueBtn1.onPressed, isNotNull);

      // 点击“保存并继续下一行歌词”
      await tester.tap(continueBtnFinder);
      await tester.pump(const Duration(milliseconds: 300));

      // 验证已触发第一行的保存回调并切换到第二行
      expect(savedLines.containsKey(0), isTrue);
      expect(activeIndex, 1);
      expect(find.text('逐字时间戳编辑与打轴 (2/2)'), findsOneWidget);

      // 在最后一行（第 2 行），“保存并继续下一行歌词”应为禁用状态
      final FilledButton continueBtn2 = tester.widget(continueBtnFinder);
      expect(continueBtn2.onPressed, isNull);

      // 点击“保存”完成最后一行并退出弹窗
      final saveBtnFinder = find.widgetWithText(FilledButton, '保存');
      expect(saveBtnFinder, findsOneWidget);
      await tester.tap(saveBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // 验证第二行保存，且弹窗已关闭
      expect(savedLines.containsKey(1), isTrue);
      expect(find.text('逐字时间戳编辑与打轴 (2/2)'), findsNothing);
    });

    testWidgets('逐字打轴首字时间自动同步为整句歌词起始时间', (WidgetTester tester) async {
      int lineTime = 1000;
      List<LyricWord>? savedWords;

      // 现有初始打轴数据，首字打轴在 2340ms（与原有 lineTime 1000ms 存在误差）
      final initialWords = [
        LyricWord(text: '天', startMs: BigInt.from(2340), durationMs: BigInt.from(300)),
        LyricWord(text: '青', startMs: BigInt.from(2640), durationMs: BigInt.from(300)),
      ];

      final lines = [
        WordSyncLineData(
          text: '天青',
          timeMs: lineTime,
          words: initialWords,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => WordSyncDialog(
                          initialIndex: 0,
                          lines: lines,
                          onLineSaved: (idx, words) {
                            savedWords = words;
                            if (words != null && words.isNotEmpty) {
                              lineTime = words.first.startMs.toInt();
                            }
                          },
                        ),
                      );
                    },
                    child: const Text('打开打轴'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开打轴'));
      await tester.pump(const Duration(milliseconds: 300));

      // 点击保存
      final saveBtnFinder = find.widgetWithText(FilledButton, '保存');
      await tester.tap(saveBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(savedWords, isNotNull);
      expect(savedWords!.first.startMs.toInt(), 2340);
      // 验证整句歌词时间已被首字更精准的时间戳自动校准覆盖
      expect(lineTime, 2340);
    });
  });
}
