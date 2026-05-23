// macOS 菜单栏歌词 — 纯函数 + 状态模型测试
//
// 本文件覆盖：
//   - `truncateByRunes` 的边界与 Unicode 处理（Property 2）
//   - `computeStatusBarTitle` 的分支正确性（Property 1）
//   - `MacosStatusBarState.copyWith` 的 EXAMPLE 测试
//
// 由于无法稳定拉取 fast_check 包，属性测试用 dart:math 的 Random 自行
// 生成输入，每条性质至少 100 次迭代（设计文档要求）。失败时直接断言出错，
// 测试报告会显示具体反例。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:jmusic/providers/app_providers.dart';
import 'package:jmusic/providers/macos_status_bar.dart';
import 'package:jmusic/src/rust/models/lyrics.dart';
import 'package:jmusic/src/rust/models/song.dart';

// ---------------------------------------------------------------------------
// 测试工具：随机输入生成器
// ---------------------------------------------------------------------------

/// 受控随机源：固定 seed 让失败可复现。
final _rng = Random(20260523);

const _alphabet = [
  'a', 'b', 'c', 'X', 'Y', 'Z',
  '0', '1', '9', ' ', '_', '-',
  '中', '文', '日', '本', '한', '글',
  '😀', '🎵', '🍎', // 多字节 emoji
];

String _randomString(int len) {
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    sb.write(_alphabet[_rng.nextInt(_alphabet.length)]);
  }
  return sb.toString();
}

Song _randomSong() {
  return Song(
    filePath: '/tmp/${_rng.nextInt(1 << 31)}.mp3',
    title: _randomString(_rng.nextInt(20) + 1),
    artist: _randomString(_rng.nextInt(15) + 1),
    album: _randomString(_rng.nextInt(15)),
    duration: 1.0 + _rng.nextDouble() * 600,
    fileSize: BigInt.from(_rng.nextInt(1 << 30)),
    format: 'mp3',
    modifiedAt: BigInt.from(_rng.nextInt(1 << 31)),
  );
}

LyricLine _randomLine(int timeMs) {
  return LyricLine(
    timeMs: BigInt.from(timeMs),
    text: _randomString(_rng.nextInt(60)),
  );
}

Lyrics _randomLyrics({int? lineCount}) {
  final n = lineCount ?? _rng.nextInt(8);
  if (n == 0) return const Lyrics(lines: []);
  // 让 timeMs 单调递增
  var t = _rng.nextInt(2000);
  final lines = <LyricLine>[];
  for (var i = 0; i < n; i++) {
    lines.add(_randomLine(t));
    t += _rng.nextInt(3000) + 1;
  }
  return Lyrics(lines: lines);
}

PlayerState _randomPlayerState() {
  final hasSong = _rng.nextBool();
  final hasLyrics = hasSong && _rng.nextBool();
  return PlayerState(
    currentSong: hasSong ? _randomSong() : null,
    lyrics: hasLyrics ? _randomLyrics() : null,
    position: Duration(milliseconds: _rng.nextInt(60_000)),
  );
}

/// 参考实现：与 truncateByRunes 等价的「显式按 rune 截断」算法，用于
/// 在测试中独立验证。如果两份实现都错了，是因为对「长度」的理解不一致，
/// 此时仍然可以通过 EXAMPLE 测试发现问题。
String _refTruncate(String s, int n) {
  final runes = s.runes.toList();
  if (runes.length <= n) return s;
  final head = String.fromCharCodes(runes.take(n));
  return '$head\u2026';
}

/// 计算「最后一个 timeMs <= position 的歌词行文本」。仅用于参考实现。
String _refCurrentLineText(Lyrics lyrics, int positionMs) {
  for (var i = lyrics.lines.length - 1; i >= 0; i--) {
    if (lyrics.lines[i].timeMs.toInt() <= positionMs) {
      return lyrics.lines[i].text;
    }
  }
  return lyrics.lines.first.text;
}

// ---------------------------------------------------------------------------
// EXAMPLE 测试：truncateByRunes
// ---------------------------------------------------------------------------

void main() {
  group('truncateByRunes (EXAMPLE)', () {
    test('短字符串原样返回', () {
      expect(truncateByRunes('abc', 5), 'abc');
      expect(truncateByRunes('abc', 3), 'abc');
      expect(truncateByRunes('', 5), '');
    });

    test('超长 ASCII 字符串截断 + 省略号', () {
      expect(truncateByRunes('abcdefghij', 3), 'abc\u2026');
    });

    test('CJK 字符按码点截断', () {
      expect(truncateByRunes('中文测试一二三', 3), '中文测\u2026');
    });

    test('emoji 不被切成两半', () {
      // 🎵 占 2 个 UTF-16 unit 但只有 1 个 rune
      const s = '🎵🎵🎵🎵🎵';
      final out = truncateByRunes(s, 2);
      expect(out, '🎵🎵\u2026');
      expect(out.runes.length, 3); // 2 + 省略号
    });

    test('maxLen=0 且非空 → 仅返回省略号', () {
      expect(truncateByRunes('abc', 0), '\u2026');
    });

    test('maxLen=0 且空 → 返回空', () {
      expect(truncateByRunes('', 0), '');
    });
  });

  // -------------------------------------------------------------------------
  // PROPERTY 测试：truncateByRunes
  // -------------------------------------------------------------------------

  group('truncateByRunes (PROPERTY)', () {
    // Feature: macos-status-bar-lyrics, Property 2: 截断的长度上界与短字符串等价
    test('Property 2: 短字符串等价 / 超长截断长度上界', () {
      for (var i = 0; i < 200; i++) {
        final n = _rng.nextInt(50);
        final len = _rng.nextInt(80);
        final s = _randomString(len);
        final out = truncateByRunes(s, n);

        if (s.runes.length <= n) {
          expect(
            out,
            s,
            reason: 'short input must be returned verbatim: '
                's="$s" (runes=${s.runes.length}), n=$n, out="$out"',
          );
        } else {
          // 长度 == n + 1，且以 U+2026 结尾
          expect(
            out.runes.length,
            n + 1,
            reason: 'truncated length must be n+1: '
                's="$s" (runes=${s.runes.length}), n=$n, out="$out"',
          );
          expect(
            out.runes.last,
            0x2026,
            reason: 'truncated output must end with …: out="$out"',
          );
          // 前 n 个码点 == 原字符串前 n 个码点
          expect(
            out.runes.take(n).toList(),
            s.runes.take(n).toList(),
            reason: 'first n runes must match input: '
                's="$s", n=$n, out="$out"',
          );
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  // EXAMPLE 测试：computeStatusBarTitle
  // -------------------------------------------------------------------------

  group('computeStatusBarTitle (EXAMPLE)', () {
    final song = Song(
      filePath: '/tmp/song.mp3',
      title: '稻香',
      artist: '周杰伦',
      album: '魔杰座',
      duration: 223.0,
      fileSize: BigInt.zero,
      format: 'mp3',
      modifiedAt: BigInt.zero,
    );

    test('currentSong == null → JMusic', () {
      const state = PlayerState();
      expect(computeStatusBarTitle(state), kStatusBarDefaultTitle);
    });

    test('lyrics == null → 标题 - 艺术家', () {
      final state = PlayerState(currentSong: song);
      expect(computeStatusBarTitle(state), '稻香 - 周杰伦');
    });

    test('lyrics 空数组 → 标题 - 艺术家', () {
      final state = PlayerState(
        currentSong: song,
        lyrics: const Lyrics(lines: []),
      );
      expect(computeStatusBarTitle(state), '稻香 - 周杰伦');
    });

    test('position 在第一行之前 → 标题 - 艺术家', () {
      final state = PlayerState(
        currentSong: song,
        lyrics: Lyrics(lines: [
          LyricLine(timeMs: BigInt.from(5000), text: '第一行'),
          LyricLine(timeMs: BigInt.from(10000), text: '第二行'),
        ]),
        position: const Duration(milliseconds: 4999),
      );
      expect(computeStatusBarTitle(state), '稻香 - 周杰伦');
    });

    test('position 命中第一行', () {
      final state = PlayerState(
        currentSong: song,
        lyrics: Lyrics(lines: [
          LyricLine(timeMs: BigInt.from(0), text: '前奏开始'),
          LyricLine(timeMs: BigInt.from(10000), text: '正式开唱'),
        ]),
        position: const Duration(milliseconds: 500),
      );
      expect(computeStatusBarTitle(state), '前奏开始');
    });

    test('position 命中最后一行', () {
      final state = PlayerState(
        currentSong: song,
        lyrics: Lyrics(lines: [
          LyricLine(timeMs: BigInt.from(0), text: 'A'),
          LyricLine(timeMs: BigInt.from(2000), text: 'B'),
          LyricLine(timeMs: BigInt.from(5000), text: 'C'),
        ]),
        position: const Duration(milliseconds: 9999),
      );
      expect(computeStatusBarTitle(state), 'C');
    });

    test('歌词文本超长 → 截断 + …', () {
      final longText = 'x' * 100;
      final state = PlayerState(
        currentSong: song,
        lyrics: Lyrics(lines: [
          LyricLine(timeMs: BigInt.from(0), text: longText),
        ]),
        position: const Duration(milliseconds: 1),
      );
      final out = computeStatusBarTitle(state);
      expect(out.runes.length, kStatusBarMaxDisplayLength + 1);
      expect(out.runes.last, 0x2026);
    });
  });

  // -------------------------------------------------------------------------
  // PROPERTY 测试：computeStatusBarTitle
  // -------------------------------------------------------------------------

  group('computeStatusBarTitle (PROPERTY)', () {
    // Feature: macos-status-bar-lyrics, Property 1: 标题计算的分支正确性
    test('Property 1: 标题计算的分支正确性', () {
      for (var i = 0; i < 200; i++) {
        final state = _randomPlayerState();
        final out = computeStatusBarTitle(state);

        // 分支 1：无歌曲
        if (state.currentSong == null) {
          expect(
            out,
            kStatusBarDefaultTitle,
            reason: 'no song → JMusic, but got "$out"',
          );
          continue;
        }

        final song = state.currentSong!;
        final lyrics = state.lyrics;
        final positionMs = state.position.inMilliseconds;

        // 分支 2：无歌词 / 空歌词 / 进度未达第一行
        if (lyrics == null ||
            lyrics.lines.isEmpty ||
            positionMs < lyrics.lines.first.timeMs.toInt()) {
          final expected =
              _refTruncate('${song.title} - ${song.artist}', kStatusBarMaxDisplayLength);
          expect(
            out,
            expected,
            reason: 'no/early lyrics → "title - artist": '
                'song.title="${song.title}", artist="${song.artist}", '
                'pos=${positionMs}, expected="$expected", got="$out"',
          );
          continue;
        }

        // 分支 3：当前行歌词
        final expectedLine =
            _refTruncate(_refCurrentLineText(lyrics, positionMs), kStatusBarMaxDisplayLength);
        expect(
          out,
          expectedLine,
          reason: 'current line mismatch: '
              'pos=${positionMs}, expected="$expectedLine", got="$out"',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // MacosStatusBarState.copyWith — EXAMPLE 测试
  // -------------------------------------------------------------------------

  group('MacosStatusBarState.copyWith', () {
    test('默认构造 enabled=true / lastPushedTitle=null', () {
      const s = MacosStatusBarState();
      expect(s.enabled, true);
      expect(s.lastPushedTitle, isNull);
    });

    test('copyWith 不带参数 → 等价对象', () {
      const s = MacosStatusBarState(enabled: false, lastPushedTitle: 'foo');
      final s2 = s.copyWith();
      expect(s2, s);
    });

    test('copyWith enabled 单字段更新', () {
      const s = MacosStatusBarState(enabled: true, lastPushedTitle: 'foo');
      final s2 = s.copyWith(enabled: false);
      expect(s2.enabled, false);
      expect(s2.lastPushedTitle, 'foo');
    });

    test('copyWith clearLastPushedTitle 显式清空', () {
      const s = MacosStatusBarState(enabled: true, lastPushedTitle: 'foo');
      final s2 = s.copyWith(clearLastPushedTitle: true);
      expect(s2.enabled, true);
      expect(s2.lastPushedTitle, isNull);
    });

    test('clearLastPushedTitle 优先于 lastPushedTitle 参数', () {
      const s = MacosStatusBarState(enabled: true, lastPushedTitle: 'foo');
      final s2 = s.copyWith(
        lastPushedTitle: 'bar',
        clearLastPushedTitle: true,
      );
      expect(s2.lastPushedTitle, isNull);
    });

    test('==/hashCode 一致', () {
      const a = MacosStatusBarState(enabled: true, lastPushedTitle: 'x');
      const b = MacosStatusBarState(enabled: true, lastPushedTitle: 'x');
      const c = MacosStatusBarState(enabled: false, lastPushedTitle: 'x');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, false);
    });
  });
}
