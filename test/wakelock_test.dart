import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/providers/wakelock_provider.dart';

/// 模拟平台屏幕常亮处理器
class FakeWakelockPlatformHandler implements WakelockPlatformHandler {
  int enableCallCount = 0;
  int disableCallCount = 0;
  bool shouldThrow = false;

  @override
  Future<void> enable() async {
    enableCallCount++;
    if (shouldThrow) {
      throw Exception('Fake enable platform error');
    }
  }

  @override
  Future<void> disable() async {
    disableCallCount++;
    if (shouldThrow) {
      throw Exception('Fake disable platform error');
    }
  }

  void reset() {
    enableCallCount = 0;
    disableCallCount = 0;
    shouldThrow = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWakelockPlatformHandler fakeHandler;
  late ProviderContainer container;

  setUp(() {
    fakeHandler = FakeWakelockPlatformHandler();
    container = ProviderContainer(
      overrides: [
        wakelockPlatformHandlerProvider.overrideWithValue(fakeHandler),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('WakelockNotifier 屏幕常亮逻辑测试', () {
    test('初始状态：无活跃页面，常亮未激活', () {
      final state = container.read(wakelockProvider);
      expect(state.activeCount, 0);
      expect(state.isAwake, false);
      expect(fakeHandler.enableCallCount, 0);
      expect(fakeHandler.disableCallCount, 0);
    });

    test('未播放时进入播放页（acquire）：计数增加但常亮不激活', () {
      final notifier = container.read(wakelockProvider.notifier);
      notifier.acquire();

      final state = container.read(wakelockProvider);
      expect(state.activeCount, 1);
      expect(state.isAwake, false);
      expect(fakeHandler.enableCallCount, 0);
    });

    test('播放中进入播放页（acquire）：常亮激活并调用 enable', () {
      // 模拟播放状态
      container.read(playerProvider.notifier).state =
          container.read(playerProvider).copyWith(isPlaying: true);

      final notifier = container.read(wakelockProvider.notifier);
      notifier.acquire();

      final state = container.read(wakelockProvider);
      expect(state.activeCount, 1);
      expect(state.isAwake, true);
      expect(fakeHandler.enableCallCount, 1);
    });

    test('播放页内暂停与继续播放：常亮状态动态切换', () {
      final playerNotifier = container.read(playerProvider.notifier);
      playerNotifier.state =
          container.read(playerProvider).copyWith(isPlaying: true);

      final notifier = container.read(wakelockProvider.notifier);
      notifier.acquire();
      expect(container.read(wakelockProvider).isAwake, true);
      expect(fakeHandler.enableCallCount, 1);

      // 暂停播放
      playerNotifier.state =
          container.read(playerProvider).copyWith(isPlaying: false);
      expect(container.read(wakelockProvider).isAwake, false);
      expect(fakeHandler.disableCallCount, 1);

      // 恢复播放
      playerNotifier.state =
          container.read(playerProvider).copyWith(isPlaying: true);
      expect(container.read(wakelockProvider).isAwake, true);
      expect(fakeHandler.enableCallCount, 2);
    });

    test('播放页跳转至全屏歌词页（多页面 acquire/release 引用计数）：全程保持常亮无中断', () {
      container.read(playerProvider.notifier).state =
          container.read(playerProvider).copyWith(isPlaying: true);

      final notifier = container.read(wakelockProvider.notifier);

      // 进入播放页
      notifier.acquire();
      expect(container.read(wakelockProvider).activeCount, 1);
      expect(container.read(wakelockProvider).isAwake, true);
      expect(fakeHandler.enableCallCount, 1);

      // 从播放页进入歌词页
      notifier.acquire();
      expect(container.read(wakelockProvider).activeCount, 2);
      expect(container.read(wakelockProvider).isAwake, true);
      // 因为已经处于常亮状态，不需要重复调用 enable
      expect(fakeHandler.enableCallCount, 1);

      // 从歌词页返回播放页
      notifier.release();
      expect(container.read(wakelockProvider).activeCount, 1);
      expect(container.read(wakelockProvider).isAwake, true);
      expect(fakeHandler.disableCallCount, 0);

      // 从播放页返回主页
      notifier.release();
      expect(container.read(wakelockProvider).activeCount, 0);
      expect(container.read(wakelockProvider).isAwake, false);
      expect(fakeHandler.disableCallCount, 1);
    });

    test('释放次数多于申请次数时安全 clamp 到 0', () {
      final notifier = container.read(wakelockProvider.notifier);
      notifier.release();
      notifier.release();

      final state = container.read(wakelockProvider);
      expect(state.activeCount, 0);
      expect(state.isAwake, false);
    });

    test('平台通道抛出异常时容错处理，不破坏应用状态', () {
      fakeHandler.shouldThrow = true;
      container.read(playerProvider.notifier).state =
          container.read(playerProvider).copyWith(isPlaying: true);

      final notifier = container.read(wakelockProvider.notifier);
      // 不应抛出未捕获异常
      expect(() => notifier.acquire(), returnsNormally);
      expect(container.read(wakelockProvider).isAwake, true);

      expect(() => notifier.release(), returnsNormally);
      expect(container.read(wakelockProvider).isAwake, false);
    });
  });

  group('KeepScreenAwake Widget 挂载与销毁生命周期测试', () {
    testWidgets('挂载组件自动 acquire，卸载组件自动 release', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: KeepScreenAwake(
              child: Text('播放页内容'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(wakelockProvider).activeCount, 1);

      // 卸载组件
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Text('其他页面'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(wakelockProvider).activeCount, 0);
    });
  });
}
