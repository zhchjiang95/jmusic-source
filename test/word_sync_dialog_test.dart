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
  });
}
