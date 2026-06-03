import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 每日听歌记录项
class DailyListeningRecord {
  /// 日期 key (yyyy-MM-dd)
  final String date;

  /// 累计听歌时长（秒）
  final int durationSeconds;

  /// 播放歌曲次数
  final int playCount;

  const DailyListeningRecord({
    required this.date,
    required this.durationSeconds,
    required this.playCount,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'duration': durationSeconds,
        'count': playCount,
      };

  factory DailyListeningRecord.fromJson(Map<String, dynamic> json) {
    return DailyListeningRecord(
      date: json['date'] as String? ?? '',
      durationSeconds: json['duration'] as int? ?? 0,
      playCount: json['count'] as int? ?? 0,
    );
  }

  DailyListeningRecord addDuration(int seconds) {
    return DailyListeningRecord(
      date: date,
      durationSeconds: durationSeconds + seconds,
      playCount: playCount,
    );
  }

  DailyListeningRecord incrementCount() {
    return DailyListeningRecord(
      date: date,
      durationSeconds: durationSeconds,
      playCount: playCount + 1,
    );
  }
}

/// 听歌日历数据持久化服务
class ListeningCalendarService {
  static ListeningCalendarService? _instance;
  static ListeningCalendarService get instance {
    _instance ??= ListeningCalendarService._();
    return _instance!;
  }

  ListeningCalendarService._();

  /// 内存中缓存的日历数据 (date_key -> record)
  Map<String, DailyListeningRecord> _records = {};
  bool _loaded = false;

  /// 脏标记：有修改待保存
  bool _dirty = false;

  /// 获取今天的日期 key
  static String todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// 格式化日期为 key
  static String dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 加载数据
  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> list = jsonDecode(content);
        _records = {
          for (final item in list)
            (item['date'] as String):
                DailyListeningRecord.fromJson(item as Map<String, dynamic>),
        };
      }
      _loaded = true;
    } catch (e) {
      debugPrint('[ListeningCalendar] 加载失败: $e');
      _records = {};
      _loaded = true;
    }
  }

  /// 保存数据到磁盘
  Future<void> save() async {
    if (!_dirty) return;
    try {
      final file = await _getFile();
      final list = _records.values.map((r) => r.toJson()).toList();
      await file.writeAsString(jsonEncode(list));
      _dirty = false;
    } catch (e) {
      debugPrint('[ListeningCalendar] 保存失败: $e');
    }
  }

  /// 累加今日听歌时长（每次调用累加指定秒数）
  void addListeningDuration(int seconds) {
    final key = todayKey();
    final existing = _records[key];
    if (existing != null) {
      _records[key] = existing.addDuration(seconds);
    } else {
      _records[key] = DailyListeningRecord(
        date: key,
        durationSeconds: seconds,
        playCount: 0,
      );
    }
    _dirty = true;
  }

  /// 记录一次播放（今日计数 +1）
  void recordPlay() {
    final key = todayKey();
    final existing = _records[key];
    if (existing != null) {
      _records[key] = existing.incrementCount();
    } else {
      _records[key] = DailyListeningRecord(
        date: key,
        durationSeconds: 0,
        playCount: 1,
      );
    }
    _dirty = true;
  }

  /// 获取指定日期的记录
  DailyListeningRecord? getRecord(String dateKey) => _records[dateKey];

  /// 获取今日记录
  DailyListeningRecord? get todayRecord => _records[todayKey()];

  /// 获取最近 N 天的记录列表（包含空值天）
  List<DailyListeningRecord?> getRecentDays(int days) {
    final today = DateTime.now();
    return List.generate(days, (i) {
      final date = today.subtract(Duration(days: days - 1 - i));
      final key = dateKey(date);
      return _records[key];
    });
  }

  /// 获取指定范围内的所有记录
  Map<String, DailyListeningRecord> getRange(DateTime start, DateTime end) {
    final result = <String, DailyListeningRecord>{};
    var current = start;
    while (!current.isAfter(end)) {
      final key = dateKey(current);
      if (_records.containsKey(key)) {
        result[key] = _records[key]!;
      }
      current = current.add(const Duration(days: 1));
    }
    return result;
  }

  /// 获取所有记录
  Map<String, DailyListeningRecord> get allRecords =>
      Map.unmodifiable(_records);

  /// 获取总听歌天数
  int get totalDays => _records.values
      .where((r) => r.durationSeconds > 0 || r.playCount > 0)
      .length;

  /// 获取总听歌时长（秒）
  int get totalDurationSeconds =>
      _records.values.fold(0, (sum, r) => sum + r.durationSeconds);

  /// 获取最大单日时长（秒）
  int get maxDailyDuration => _records.values.isEmpty
      ? 0
      : _records.values
          .map((r) => r.durationSeconds)
          .reduce((a, b) => a > b ? a : b);

  /// 获取当前连续打卡天数
  int get currentStreak {
    int streak = 0;
    var date = DateTime.now();
    while (true) {
      final key = dateKey(date);
      final record = _records[key];
      if (record != null && (record.durationSeconds > 0 || record.playCount > 0)) {
        streak++;
        date = date.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  /// 获取数据文件
  Future<File> _getFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory('${appDir.path}/.jmusic');
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    return File('${dataDir.path}/listening_calendar.json');
  }
}
