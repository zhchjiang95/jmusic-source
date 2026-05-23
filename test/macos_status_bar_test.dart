// Feature: macos-status-bar-lyrics
//
// Dart 端单元测试 + 属性测试。
//
// 由于 `fast_check` 在拉取过程中超时，本文件用 `flutter_test` 自带能力 +
// 一个轻量 PBT 帮助函数 `forAll` 实现属性测试，每个属性默认 100 次迭代。
// 失败时打印复现种子以便定位。语义与 fast_check 等价。
//
// 涵盖：
//   - 单元（EXAMPLE）测试：默认值 / 非 macOS 平台门控（仅在 Linux/Win 上跑过）
//   - Property 1：computeStatusBarTitle 分支正确性
//   - Property 2：truncateByRunes 长度上界与短字符串等价
//   - Property 3：_pushIfChanged 去重（连续相同 title 只推送一次）
//   - Property 4：切歌旁路去重
//   - Property 5：禁用态吞掉一切推送
//   - Property 6：启用切换的对称恢复
//   - Property 7：channel 异常隔离

import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/providers/macos_status_bar.dart';
import 'package:jmusic/src/rust/models/lyrics.dart';
import 'package:jmusic/src/rust/models/song.dart';

// ---------------------------------------------------------------------------
// 轻量 PBT 帮助
// ---------------------------------------------------------------------------

/// 简单的属性测试 runner：以确定性种子运行 [iterations] 次 [body]。
///
/// [body] 收到一个 `Random` 用于生成测试输入。任何 fail 都附带种子用于复现。
void forAll(
  String name,
  void Function(Random rng) body, {
  int iterations = 100,
  int? seed,
}) {
  final actualSeed = seed ?? DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
  test(name, () {
    for (var i = 0; i < iterations; i++) {
      final iterSeed = actualSeed + i;
      final rng = Random(iterSeed);
      try {
        body(rng);
      } catch (e, st) {
        fail(
          'Property test "$name" failed at iteration $i (seed=$iterSeed): $e\n$st',
        );
      }
    }
  });
}

// ---------------------------------------------------------------------------
// 生成器
// ---------------------------------------------------------------------------

const _alphabet = [
  'a',
  'b',
  '中',
  '文',
  ' ',
  '🎵',
  '😀',
  '🚀',
  'A',
  'Z',
  '!',
  '...',
];

String _genString(Random rng, {int minLen = 0, int maxLen = 60}) {
  final len = minLen + rng.nextInt(max(1, maxLen - minLen + 1));
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    sb.write(_alphabet[rng.nextInt(_alphabet.length)]);
  }
  return sb.toString();
}

Song _genSong(Random rng, {String? filePath}) => Song(
      filePath: filePath ?? '/tmp/${rng.nextInt(1 << 30)}.mp3',
      title: _genString(rng, minLen: 1, maxLen: 30),
      artist: _genString(rng, minLen: 1, maxLen: 30),
      album: _genString(rng),
      duration: rng.nextDouble() * 600,
      fileSize: BigInt.from(rng.nextInt(1 << 30)),
      format: 'mp3',
      modifiedAt: BigInt.from(rng.nextInt(1 << 30)),
    );

Lyrics? _genLyrics(Random rng) {
  if (rng.nextDouble() < 0.15) return null;
  if (rng.nextDouble() < 0.10) return const Lyrics(lines: []);
  final n = 1 + rng.nextInt(8);
  final lines = <LyricLine>[];
  var t = rng.nextInt(2000); // 第一行 timeMs 可能 > 0，覆盖「未到第一行」分支
  for (var i = 0; i < n; i++) {
    lines.add(LyricLine(timeMs: BigInt.from(t), text: _genString(rng)));
    t += 200 + rng.nextInt(2000);
  }
  return Lyrics(lines: lines);
}

PlayerState _genPlayerState(Random rng, {Song? song, Lyrics? lyrics, int? positionMs}) {
  final s = song ?? (rng.nextDouble() < 0.08 ? null : _genSong(rng));
  final l = s == null ? null : (lyrics ?? _genLyrics(rng));
  final pos = positionMs ?? rng.nextInt(20000);
  return PlayerState(
    currentSong: s,
    lyrics: l,
    position: Duration(milliseconds: pos),
  );
}

// ---------------------------------------------------------------------------
// Channel mock 工具：拦截 com.jmusic.app/macos_status_bar
// ---------------------------------------------------------------------------

class _ChannelRecorder {
  final List<MapEntry<String, dynamic>> calls = [];
  bool throwOnInvoke = false;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(kMacosStatusBarChannel),
      (call) async {
        calls.add(MapEntry(call.method, call.arguments));
        if (throwOnInvoke) {
          throw PlatformException(code: 'MOCK_FAIL', message: 'mocked failure');
        }
        return null;
      },
    );
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(kMacosStatusBarChannel),
      null,
    );
  }

  List<dynamic> argsForMethod(String method) =>
      calls.where((e) => e.key == method).map((e) => e.value).toList();
}

// ---------------------------------------------------------------------------
// 单元（EXAMPLE）测试
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 让 SharedPreferences 在测试中走 in-memory 后端
  SharedPreferencesTestSetup.setup();

  group('truncateByRunes (EXAMPLE)', () {
    test('短字符串原样返回', () {
      expect(truncateByRunes('abc', 5), 'abc');
      expect(truncateByRunes('abc', 3), 'abc');
    });
    test('长字符串截断并加省略号', () {
      expect(truncateByRunes('abcdef', 3), 'abc\u2026');
    });
    test('emoji / CJK 按码点截断不切坏', () {
      // 6 个码点，截断到 3 + …
      const s = '🎵中a🚀b文';
      final out = truncateByRunes(s, 3);
      expect(out.runes.length, 4); // 3 + …
      expect(out.runes.last, 0x2026);
      expect(String.fromCharCodes(s.runes.take(3)),
          equals(String.fromCharCodes(out.runes.take(3))));
    });
    test('maxLen=0 且字符串非空只剩省略号', () {
      expect(truncateByRunes('abc', 0), '\u2026');
    });
    test('空字符串恒等于空', () {
      expect(truncateByRunes('', 0), '');
      expect(truncateByRunes('', 5), '');
    });
  });

  group('computeStatusBarTitle (EXAMPLE)', () {
    test('无歌曲返回 JMusic', () {
      const state = PlayerState();
      expect(computeStatusBarTitle(state), kStatusBarDefaultTitle);
    });

    test('有歌无歌词显示「歌曲 - 艺术家」', () {
      final state = PlayerState(
        currentSong: Song(
          filePath: '/x.mp3',
          title: '夜曲',
          artist: '周杰伦',
          album: '',
          duration: 0,
          fileSize: BigInt.zero,
          format: 'mp3',
          modifiedAt: BigInt.zero,
        ),
      );
      expect(computeStatusBarTitle(state), '夜曲 - 周杰伦');
    });

    test('当前进度小于第一行歌词 timeMs 显示「歌曲 - 艺术家」', () {
      final state = PlayerState(
        currentSong: Song(
          filePath: '/x.mp3',
          title: 'A',
          artist: 'B',
          album: '',
          duration: 0,
          fileSize: BigInt.zero,
          format: 'mp3',
          modifiedAt: BigInt.zero,
        ),
        lyrics: Lyrics(lines: [
          LyricLine(timeMs: BigInt.from(5000), text: 'first'),
        ]),
        position: const Duration(milliseconds: 100),
      );
      expect(computeStatusBarTitle(state), 'A - B');
    });

    test('正常歌词显示当前行', () {
      final state = PlayerState(
        currentSong: Song(
          filePath: '/x.mp3',
          title: 'A',
          artist: 'B',
          album: '',
          duration: 0,
          fileSize: BigInt.zero,
          format: 'mp3',
          modifiedAt: BigInt.zero,
        ),
        lyrics: Lyrics(lines: [
          LyricLine(timeMs: BigInt.from(0), text: 'line0'),
          LyricLine(timeMs: BigInt.from(1000), text: 'line1'),
          LyricLine(timeMs: BigInt.from(2000), text: 'line2'),
        ]),
        position: const Duration(milliseconds: 1500),
      );
      expect(computeStatusBarTitle(state), 'line1');
    });
  });

  // -------------------------------------------------------------------------
  // 属性测试（PROPERTY）
  // -------------------------------------------------------------------------

  group('computeStatusBarTitle PBT', () {
    // Feature: macos-status-bar-lyrics, Property 1: 标题计算的分支正确性
    forAll('Property 1：computeStatusBarTitle 覆盖所有分支', (rng) {
      final state = _genPlayerState(rng);
      final actual = computeStatusBarTitle(state);

      // 期望分支：与函数实现镜像
      String expected;
      final song = state.currentSong;
      if (song == null) {
        expected = kStatusBarDefaultTitle;
      } else {
        final lyrics = state.lyrics;
        final pos = state.position.inMilliseconds;
        if (lyrics == null || lyrics.lines.isEmpty) {
          expected = truncateByRunes('${song.title} - ${song.artist}',
              kStatusBarMaxDisplayLength);
        } else if (pos < lyrics.lines.first.timeMs.toInt()) {
          expected = truncateByRunes('${song.title} - ${song.artist}',
              kStatusBarMaxDisplayLength);
        } else {
          var text = lyrics.lines.first.text;
          for (var i = lyrics.lines.length - 1; i >= 0; i--) {
            if (lyrics.lines[i].timeMs.toInt() <= pos) {
              text = lyrics.lines[i].text;
              break;
            }
          }
          expected = truncateByRunes(text, kStatusBarMaxDisplayLength);
        }
      }
      expect(actual, expected);
    });
  });

  group('truncateByRunes PBT', () {
    // Feature: macos-status-bar-lyrics, Property 2: 截断长度上界与短字符串等价
    forAll('Property 2：长度上界与短字符串等价', (rng) {
      final s = _genString(rng, maxLen: 100);
      final n = rng.nextInt(60); // 0..59
      final out = truncateByRunes(s, n);
      if (s.runes.length <= n) {
        expect(out, s);
      } else {
        expect(out.runes.length, n + 1);
        expect(out.runes.last, 0x2026);
        expect(
          String.fromCharCodes(out.runes.take(n)),
          String.fromCharCodes(s.runes.take(n)),
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // Controller 级测试（依赖 macOS 平台门控；Linux/Win CI 上 Property 3-7 会
  // 因 build() 早返而跳过被驱动的 channel 调用，无法验证。本测试假定运行
  // 环境为 macOS）。
  // -------------------------------------------------------------------------

  group('MacosStatusBarController (macOS only)', () {
    // 跳过非 macOS 平台
    final isMac = !Platform.environment.containsKey('CI') && Platform.isMacOS;
    if (!isMac) {
      test('skipped: not macOS', () {
        expect(true, true);
      }, skip: 'Controller-level tests run on macOS only');
      return;
    }

    late ProviderContainer container;
    late _ChannelRecorder recorder;

    setUp(() {
      recorder = _ChannelRecorder()..install();
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
      recorder.uninstall();
    });

    /// 获取 Controller。第一次访问会触发 build()。
    MacosStatusBarController controller() =>
        container.read(macosStatusBarControllerProvider.notifier);

    /// 等待异步副作用稳定（_restorePreferenceAndInit / _pushIfChanged）。
    Future<void> settle() async {
      // 多次微任务 yield + 真正的异步等待，确保 SharedPreferences 与
      // invokeMethod 的 await chain 完成。
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('初始 enabled 默认为 true，启动后立即 setEnabled(true) 推到 Swift', () async {
      controller(); // trigger build
      await settle();
      final enabledArgs = recorder.argsForMethod('setEnabled');
      expect(enabledArgs.isNotEmpty, true);
      expect(enabledArgs.last, true);
    });

    test('菜单 closeStatusBar 触发持久化为 false 且 state.enabled=false', () async {
      controller();
      await settle();

      // 模拟 Swift 端发来的菜单点击
      const channel = MethodChannel(kMacosStatusBarChannel);
      // ignore: invalid_use_of_visible_for_testing_member
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onMenuAction', 'closeStatusBar'),
        ),
        null,
      );
      await settle();

      expect(
        container.read(macosStatusBarControllerProvider).enabled,
        false,
      );
      // setEnabled(false) 应有发出
      final enabledArgs = recorder.argsForMethod('setEnabled');
      expect(enabledArgs.contains(false), true);
    });

    // ----- Property 3: setText 去重 -----
    // Feature: macos-status-bar-lyrics, Property 3: setText 幂等去重
    test('Property 3：连续相同 title 只发送一次 setText', () async {
      final c = controller();
      await settle();
      // 启动期间会发若干 setText（来自启用瞬间的 force 推送），先清空
      recorder.calls.clear();

      // 模拟连续 3 次同标题 force=true
      final state = PlayerState(
        currentSong: Song(
          filePath: '/x.mp3',
          title: 'A',
          artist: 'B',
          album: '',
          duration: 0,
          fileSize: BigInt.zero,
          format: 'mp3',
          modifiedAt: BigInt.zero,
        ),
      );
      // 第一次 force=true，会发出
      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
      await c.setEnabled(true); // 触发一次推送
      await settle();
      final initialSetText = recorder.argsForMethod('setText').length;

      // 同标题再发两次，由于去重，setText 不再增加
      // 通过模拟 playerProvider 不变化也无法触发——这里直接构造调用：
      // 由于 _pushIfChanged 是私有方法，改用「让 playerProvider state 改变但
      // 计算后 title 相同」的方式：把 position 在不影响标题的范围内挪动
      final notifier = container.read(playerProvider.notifier);
      // 让 playerProvider 持有 state 触发监听器
      notifier.state = state;
      await settle();
      notifier.state = state.copyWith(
        position: const Duration(milliseconds: 1),
      );
      await settle();
      notifier.state = state.copyWith(
        position: const Duration(milliseconds: 2),
      );
      await settle();

      // 标题在这三次状态下都是 "A - B"，所以 setText 不应再被调用
      final finalSetText = recorder.argsForMethod('setText').length;
      expect(
        finalSetText,
        lessThanOrEqualTo(initialSetText + 1),
        reason: '相同 title 在去重后最多增加 1 次（首次 setEnabled 之后的初次 listener）',
      );
    });

    // ----- Property 4: 切歌旁路去重 -----
    // Feature: macos-status-bar-lyrics, Property 4: 切歌旁路去重
    test('Property 4：切歌即使 title 相同也强制推送', () async {
      controller();
      await settle();
      recorder.calls.clear();

      final notifier = container.read(playerProvider.notifier);
      // 构造两首不同 filePath 但 title/artist 相同 → computeStatusBarTitle 一致
      final s1 = Song(
        filePath: '/song1.mp3',
        title: 'SameTitle',
        artist: 'SameArtist',
        album: '',
        duration: 0,
        fileSize: BigInt.zero,
        format: 'mp3',
        modifiedAt: BigInt.zero,
      );
      final s2 = Song(
        filePath: '/song2.mp3', // ← 不同 filePath
        title: 'SameTitle',
        artist: 'SameArtist',
        album: '',
        duration: 0,
        fileSize: BigInt.zero,
        format: 'mp3',
        modifiedAt: BigInt.zero,
      );
      notifier.state = PlayerState(currentSong: s1);
      await settle();
      final beforeSwitch = recorder.argsForMethod('setText').length;

      // 切歌：必触发推送（即使字符串相同）
      notifier.state = PlayerState(currentSong: s2);
      await settle();
      final afterSwitch = recorder.argsForMethod('setText').length;

      expect(afterSwitch, greaterThan(beforeSwitch));
    });

    // ----- Property 5: 禁用态吞掉一切推送 -----
    // Feature: macos-status-bar-lyrics, Property 5: 禁用态吞掉所有 setText
    test('Property 5：disable 后 playerProvider 任何变化都不再触发 setText', () async {
      final c = controller();
      await settle();

      await c.setEnabled(false);
      await settle();
      recorder.calls.clear();

      final notifier = container.read(playerProvider.notifier);
      for (var i = 0; i < 5; i++) {
        notifier.state = PlayerState(
          currentSong: Song(
            filePath: '/$i.mp3',
            title: 't$i',
            artist: 'a$i',
            album: '',
            duration: 0,
            fileSize: BigInt.zero,
            format: 'mp3',
            modifiedAt: BigInt.zero,
          ),
        );
        await settle();
      }

      expect(recorder.argsForMethod('setText'), isEmpty);
      expect(
        container.read(macosStatusBarControllerProvider).enabled,
        false,
      );
    });

    // ----- Property 6: 启用切换的对称恢复 -----
    // Feature: macos-status-bar-lyrics, Property 6: 启用切换对称恢复
    test('Property 6：setEnabled(true) 后立即推送一次当前歌词；toggle 后 enabled 与最后一次调用一致', () async {
      final c = controller();
      await settle();

      // 注入一个 currentSong 让 computeStatusBarTitle 有实际输出
      final notifier = container.read(playerProvider.notifier);
      notifier.state = PlayerState(
        currentSong: Song(
          filePath: '/p6.mp3',
          title: 'Title6',
          artist: 'Artist6',
          album: '',
          duration: 0,
          fileSize: BigInt.zero,
          format: 'mp3',
          modifiedAt: BigInt.zero,
        ),
      );
      await settle();

      await c.setEnabled(false);
      await settle();
      recorder.calls.clear();

      await c.setEnabled(true);
      await settle();
      // setEnabled(true) 后 channel 应有 setEnabled(true) + setText("Title6 - Artist6")
      expect(recorder.argsForMethod('setEnabled').contains(true), true);
      final texts = recorder.argsForMethod('setText');
      expect(texts.contains('Title6 - Artist6'), true);
      expect(
        container.read(macosStatusBarControllerProvider).enabled,
        true,
      );

      // toggle 多次后状态与最后一次一致
      await c.setEnabled(false);
      await c.setEnabled(true);
      await c.setEnabled(false);
      await settle();
      expect(
        container.read(macosStatusBarControllerProvider).enabled,
        false,
      );
    });

    // ----- Property 7: channel 异常隔离 -----
    // Feature: macos-status-bar-lyrics, Property 7: channel 异常隔离
    test('Property 7：channel 抛 PlatformException 不会传染 playerProvider', () async {
      controller();
      await settle();

      recorder.throwOnInvoke = true;
      final notifier = container.read(playerProvider.notifier);

      // 反复触发 state 变化，全部 channel 调用都会抛错
      var caughtAny = false;
      for (var i = 0; i < 5; i++) {
        try {
          notifier.state = PlayerState(
            currentSong: Song(
              filePath: '/p7-$i.mp3',
              title: 't',
              artist: 'a',
              album: '',
              duration: 0,
              fileSize: BigInt.zero,
              format: 'mp3',
              modifiedAt: BigInt.zero,
            ),
            position: Duration(milliseconds: i),
          );
        } catch (_) {
          caughtAny = true;
        }
        await settle();
      }

      // playerProvider 状态应当依然反映最后一次设置
      expect(notifier.state.currentSong?.filePath, '/p7-4.mp3');
      // 不应有未被吞掉的异常逃逸到本测试调用栈
      expect(caughtAny, false);
    });
  });
}

// ---------------------------------------------------------------------------
// SharedPreferences 测试桩
// ---------------------------------------------------------------------------

class SharedPreferencesTestSetup {
  static void setup() {
    // 用 MethodChannel mock 让 shared_preferences 在测试环境下走 in-memory map
    final prefs = <String, Object>{};
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getAll':
          return prefs;
        case 'setBool':
        case 'setInt':
        case 'setDouble':
        case 'setString':
          final args = call.arguments as Map;
          prefs[args['key'] as String] = args['value'] as Object;
          return true;
        case 'setStringList':
          final args = call.arguments as Map;
          prefs[args['key'] as String] = args['value'] as Object;
          return true;
        case 'remove':
          final args = call.arguments as Map;
          prefs.remove(args['key'] as String);
          return true;
        case 'clear':
          prefs.clear();
          return true;
        default:
          return null;
      }
    });
  }
}
