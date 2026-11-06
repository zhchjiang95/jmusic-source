import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmusic/pages/player_page.dart';
import 'package:jmusic/widgets/lyrics_view.dart';

void main() {
  group('PlayerPage 左右双栏与纯享歌词舞台测试', () {
    testWidgets('宽屏下正确渲染左右双栏结构、完整歌词舞台及纯享模式切换', (WidgetTester tester) async {
      // 设置宽屏桌面尺寸 (1200 x 800)
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PlayerPage(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // 验证顶部操作栏按钮与右侧 LyricsView 存在
      expect(find.text('收起'), findsOneWidget);
      expect(find.text('纯享歌词'), findsOneWidget);
      expect(find.byType(LyricsView), findsOneWidget);

      // 验证无歌词时显示前卫毛玻璃空状态引导卡片
      expect(find.text('当前曲目暂无歌词'), findsOneWidget);
      expect(find.text('打开歌词编辑器'), findsOneWidget);

      // 点击“纯享歌词”切换至页内全屏纯享模式
      await tester.tap(find.text('纯享歌词'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // 验证按钮已变为“双栏舞台”
      expect(find.text('双栏舞台'), findsOneWidget);

      // 再次点击“双栏舞台”恢复左右分栏
      await tester.tap(find.text('双栏舞台'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('纯享歌词'), findsOneWidget);
    });

    testWidgets('静止 3 秒自动隐藏操作按钮，鼠标移动后立即恢复显示', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PlayerPage(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // 初始状态下操作控件可见
      LyricsView lyricsView = tester.widget<LyricsView>(find.byType(LyricsView));
      expect(lyricsView.controlsVisible, isTrue);

      // 经过 3.1 秒无操作后，自动隐藏操作按钮
      await tester.pump(const Duration(milliseconds: 3100));
      lyricsView = tester.widget<LyricsView>(find.byType(LyricsView));
      expect(lyricsView.controlsVisible, isFalse);

      // 模拟鼠标移动进入，立即恢复显示操作按钮
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(400, 300));
      addTearDown(gesture.removePointer);
      await gesture.moveTo(const Offset(450, 320));
      await tester.pump();

      lyricsView = tester.widget<LyricsView>(find.byType(LyricsView));
      expect(lyricsView.controlsVisible, isTrue);
    });
  });
}

