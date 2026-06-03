import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:jmusic/services/listening_calendar_service.dart';
import 'package:jmusic/services/play_history_service.dart';
import 'package:jmusic/src/rust/api/play_stats.dart' as rust_play_stats;

/// 成就类别
enum AchievementCategory {
  /// 听歌时长相关
  duration,

  /// 播放次数相关
  playCount,

  /// 连续打卡相关
  streak,

  /// 探索多样性相关
  exploration,

  /// 特殊时刻相关
  moment,
}

/// 成就稀有度
enum AchievementRarity {
  /// 普通（容易达成）
  common,

  /// 稀有（需要一定积累）
  rare,

  /// 史诗（需要大量积累）
  epic,

  /// 传说（极难达成）
  legendary,
}

/// 单个成就定义
class Achievement {
  final String id;
  final String icon;
  final String title;
  final String description;
  final AchievementCategory category;
  final AchievementRarity rarity;

  /// 判断是否解锁的函数
  final bool Function(AchievementContext ctx) checkUnlocked;

  /// 进度（0.0 ~ 1.0），null 表示非渐进式
  final double? Function(AchievementContext ctx)? getProgress;

  const Achievement({
    required this.id,
    required this.icon,
    required this.title,
    required this.description,
    required this.category,
    required this.rarity,
    required this.checkUnlocked,
    this.getProgress,
  });
}

/// 成就检查上下文（汇集各项统计数据）
class AchievementContext {
  final int totalPlayCount; // 总播放次数
  final int totalDurationMinutes; // 总听歌时长（分钟）
  final int totalDays; // 总听歌天数
  final int currentStreak; // 当前连续打卡天数
  final int distinctSongs; // 不同歌曲数
  final int distinctArtists; // 不同艺术家数
  final int maxDailyMinutes; // 单日最长听歌时长
  final bool hasLateNightPlay; // 是否有凌晨播放
  final bool hasEarlyMorningPlay; // 是否有清晨播放
  final int maxSingleSongCount; // 单曲最高播放次数
  final int totalHours; // 总小时数

  const AchievementContext({
    required this.totalPlayCount,
    required this.totalDurationMinutes,
    required this.totalDays,
    required this.currentStreak,
    required this.distinctSongs,
    required this.distinctArtists,
    required this.maxDailyMinutes,
    required this.hasLateNightPlay,
    required this.hasEarlyMorningPlay,
    required this.maxSingleSongCount,
    required this.totalHours,
  });
}

/// 成就解锁记录
class AchievementUnlock {
  final String achievementId;
  final int unlockedAt; // Unix 时间戳（毫秒）

  const AchievementUnlock({
    required this.achievementId,
    required this.unlockedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': achievementId,
        'at': unlockedAt,
      };

  factory AchievementUnlock.fromJson(Map<String, dynamic> json) {
    return AchievementUnlock(
      achievementId: json['id'] as String? ?? '',
      unlockedAt: json['at'] as int? ?? 0,
    );
  }

  DateTime get unlockedDateTime =>
      DateTime.fromMillisecondsSinceEpoch(unlockedAt);
}

/// 成就系统服务
class AchievementService {
  static AchievementService? _instance;
  static AchievementService get instance {
    _instance ??= AchievementService._();
    return _instance!;
  }

  AchievementService._();

  /// 已解锁的成就 (id -> unlock record)
  Map<String, AchievementUnlock> _unlocked = {};
  bool _loaded = false;
  bool _dirty = false;

  /// 新解锁的成就（用于通知 UI 弹窗）
  final List<Achievement> _newlyUnlocked = [];

  /// 所有成就定义
  static final List<Achievement> allAchievements = [
    // ─── 播放次数 ─────────────────────────────────────────────
    Achievement(
      id: 'first_play',
      icon: '🎵',
      title: '初次邂逅',
      description: '播放第一首歌',
      category: AchievementCategory.playCount,
      rarity: AchievementRarity.common,
      checkUnlocked: (ctx) => ctx.totalPlayCount >= 1,
    ),
    Achievement(
      id: 'play_10',
      icon: '🎶',
      title: '小试牛刀',
      description: '累计播放 10 首歌',
      category: AchievementCategory.playCount,
      rarity: AchievementRarity.common,
      checkUnlocked: (ctx) => ctx.totalPlayCount >= 10,
      getProgress: (ctx) => (ctx.totalPlayCount / 10).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'play_50',
      icon: '🎧',
      title: '音乐爱好者',
      description: '累计播放 50 首歌',
      category: AchievementCategory.playCount,
      rarity: AchievementRarity.common,
      checkUnlocked: (ctx) => ctx.totalPlayCount >= 50,
      getProgress: (ctx) => (ctx.totalPlayCount / 50).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'play_100',
      icon: '💯',
      title: '百首达成',
      description: '累计播放 100 首歌',
      category: AchievementCategory.playCount,
      rarity: AchievementRarity.rare,
      checkUnlocked: (ctx) => ctx.totalPlayCount >= 100,
      getProgress: (ctx) => (ctx.totalPlayCount / 100).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'play_500',
      icon: '🏆',
      title: '资深乐迷',
      description: '累计播放 500 首歌',
      category: AchievementCategory.playCount,
      rarity: AchievementRarity.epic,
      checkUnlocked: (ctx) => ctx.totalPlayCount >= 500,
      getProgress: (ctx) => (ctx.totalPlayCount / 500).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'play_1000',
      icon: '👑',
      title: '千曲大师',
      description: '累计播放 1000 首歌',
      category: AchievementCategory.playCount,
      rarity: AchievementRarity.legendary,
      checkUnlocked: (ctx) => ctx.totalPlayCount >= 1000,
      getProgress: (ctx) => (ctx.totalPlayCount / 1000).clamp(0.0, 1.0),
    ),

    // ─── 听歌时长 ─────────────────────────────────────────────
    Achievement(
      id: 'hour_1',
      icon: '⏱️',
      title: '一小时入门',
      description: '累计听歌 1 小时',
      category: AchievementCategory.duration,
      rarity: AchievementRarity.common,
      checkUnlocked: (ctx) => ctx.totalHours >= 1,
      getProgress: (ctx) => (ctx.totalDurationMinutes / 60).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'hour_10',
      icon: '🕐',
      title: '十小时沉浸',
      description: '累计听歌 10 小时',
      category: AchievementCategory.duration,
      rarity: AchievementRarity.rare,
      checkUnlocked: (ctx) => ctx.totalHours >= 10,
      getProgress: (ctx) => (ctx.totalHours / 10).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'hour_50',
      icon: '⌛',
      title: '五十小时深度',
      description: '累计听歌 50 小时',
      category: AchievementCategory.duration,
      rarity: AchievementRarity.epic,
      checkUnlocked: (ctx) => ctx.totalHours >= 50,
      getProgress: (ctx) => (ctx.totalHours / 50).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'hour_100',
      icon: '🌟',
      title: '百小时传奇',
      description: '累计听歌 100 小时',
      category: AchievementCategory.duration,
      rarity: AchievementRarity.legendary,
      checkUnlocked: (ctx) => ctx.totalHours >= 100,
      getProgress: (ctx) => (ctx.totalHours / 100).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'daily_60min',
      icon: '🔥',
      title: '一小时马拉松',
      description: '单日听歌超过 60 分钟',
      category: AchievementCategory.duration,
      rarity: AchievementRarity.rare,
      checkUnlocked: (ctx) => ctx.maxDailyMinutes >= 60,
    ),
    Achievement(
      id: 'daily_120min',
      icon: '🌋',
      title: '两小时狂热',
      description: '单日听歌超过 120 分钟',
      category: AchievementCategory.duration,
      rarity: AchievementRarity.epic,
      checkUnlocked: (ctx) => ctx.maxDailyMinutes >= 120,
    ),

    // ─── 连续打卡 ─────────────────────────────────────────────
    Achievement(
      id: 'streak_3',
      icon: '📅',
      title: '三天坚持',
      description: '连续 3 天听歌',
      category: AchievementCategory.streak,
      rarity: AchievementRarity.common,
      checkUnlocked: (ctx) => ctx.currentStreak >= 3,
      getProgress: (ctx) => (ctx.currentStreak / 3).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'streak_7',
      icon: '🗓️',
      title: '一周不间断',
      description: '连续 7 天听歌',
      category: AchievementCategory.streak,
      rarity: AchievementRarity.rare,
      checkUnlocked: (ctx) => ctx.currentStreak >= 7,
      getProgress: (ctx) => (ctx.currentStreak / 7).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'streak_30',
      icon: '📆',
      title: '月度达人',
      description: '连续 30 天听歌',
      category: AchievementCategory.streak,
      rarity: AchievementRarity.epic,
      checkUnlocked: (ctx) => ctx.currentStreak >= 30,
      getProgress: (ctx) => (ctx.currentStreak / 30).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'streak_100',
      icon: '💎',
      title: '百日传说',
      description: '连续 100 天听歌',
      category: AchievementCategory.streak,
      rarity: AchievementRarity.legendary,
      checkUnlocked: (ctx) => ctx.currentStreak >= 100,
      getProgress: (ctx) => (ctx.currentStreak / 100).clamp(0.0, 1.0),
    ),

    // ─── 探索多样性 ───────────────────────────────────────────
    Achievement(
      id: 'songs_10',
      icon: '🗂️',
      title: '小小收藏',
      description: '听过 10 首不同的歌',
      category: AchievementCategory.exploration,
      rarity: AchievementRarity.common,
      checkUnlocked: (ctx) => ctx.distinctSongs >= 10,
      getProgress: (ctx) => (ctx.distinctSongs / 10).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'songs_50',
      icon: '📚',
      title: '曲库达人',
      description: '听过 50 首不同的歌',
      category: AchievementCategory.exploration,
      rarity: AchievementRarity.rare,
      checkUnlocked: (ctx) => ctx.distinctSongs >= 50,
      getProgress: (ctx) => (ctx.distinctSongs / 50).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'songs_200',
      icon: '🎪',
      title: '博览群曲',
      description: '听过 200 首不同的歌',
      category: AchievementCategory.exploration,
      rarity: AchievementRarity.epic,
      checkUnlocked: (ctx) => ctx.distinctSongs >= 200,
      getProgress: (ctx) => (ctx.distinctSongs / 200).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'artists_5',
      icon: '🎤',
      title: '五位歌手',
      description: '听过 5 位不同的歌手',
      category: AchievementCategory.exploration,
      rarity: AchievementRarity.common,
      checkUnlocked: (ctx) => ctx.distinctArtists >= 5,
      getProgress: (ctx) => (ctx.distinctArtists / 5).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'artists_20',
      icon: '🎙️',
      title: '音乐杂食者',
      description: '听过 20 位不同的歌手',
      category: AchievementCategory.exploration,
      rarity: AchievementRarity.rare,
      checkUnlocked: (ctx) => ctx.distinctArtists >= 20,
      getProgress: (ctx) => (ctx.distinctArtists / 20).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'single_song_50',
      icon: '🔄',
      title: '单曲循环王',
      description: '同一首歌播放超过 50 次',
      category: AchievementCategory.exploration,
      rarity: AchievementRarity.epic,
      checkUnlocked: (ctx) => ctx.maxSingleSongCount >= 50,
      getProgress: (ctx) => (ctx.maxSingleSongCount / 50).clamp(0.0, 1.0),
    ),

    // ─── 特殊时刻 ─────────────────────────────────────────────
    Achievement(
      id: 'night_owl',
      icon: '🦉',
      title: '夜猫子',
      description: '凌晨 0-4 点还在听歌',
      category: AchievementCategory.moment,
      rarity: AchievementRarity.rare,
      checkUnlocked: (ctx) => ctx.hasLateNightPlay,
    ),
    Achievement(
      id: 'early_bird',
      icon: '🐦',
      title: '早起的鸟儿',
      description: '早晨 5-6 点听歌',
      category: AchievementCategory.moment,
      rarity: AchievementRarity.rare,
      checkUnlocked: (ctx) => ctx.hasEarlyMorningPlay,
    ),
    Achievement(
      id: 'days_30',
      icon: '🎯',
      title: '月度旅程',
      description: '累计 30 天有听歌记录',
      category: AchievementCategory.moment,
      rarity: AchievementRarity.rare,
      checkUnlocked: (ctx) => ctx.totalDays >= 30,
      getProgress: (ctx) => (ctx.totalDays / 30).clamp(0.0, 1.0),
    ),
    Achievement(
      id: 'days_100',
      icon: '🏅',
      title: '百日征程',
      description: '累计 100 天有听歌记录',
      category: AchievementCategory.moment,
      rarity: AchievementRarity.epic,
      checkUnlocked: (ctx) => ctx.totalDays >= 100,
      getProgress: (ctx) => (ctx.totalDays / 100).clamp(0.0, 1.0),
    ),
  ];

  /// 是否已加载
  bool get isLoaded => _loaded;

  /// 已解锁成就数
  int get unlockedCount => _unlocked.length;

  /// 总成就数
  int get totalCount => allAchievements.length;

  /// 获取新解锁的成就（弹出后清空）
  List<Achievement> popNewlyUnlocked() {
    final list = List<Achievement>.from(_newlyUnlocked);
    _newlyUnlocked.clear();
    return list;
  }

  /// 加载解锁记录
  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> list = jsonDecode(content);
        _unlocked = {
          for (final item in list)
            (item['id'] as String):
                AchievementUnlock.fromJson(item as Map<String, dynamic>),
        };
      }
      _loaded = true;
    } catch (e) {
      debugPrint('[Achievement] 加载失败: $e');
      _unlocked = {};
      _loaded = true;
    }
  }

  /// 保存
  Future<void> save() async {
    if (!_dirty) return;
    try {
      final file = await _getFile();
      final list = _unlocked.values.map((u) => u.toJson()).toList();
      await file.writeAsString(jsonEncode(list));
      _dirty = false;
    } catch (e) {
      debugPrint('[Achievement] 保存失败: $e');
    }
  }

  /// 检查并解锁成就（每次播放后调用）
  void checkAndUnlock() {
    final ctx = _buildContext();

    for (final achievement in allAchievements) {
      if (_unlocked.containsKey(achievement.id)) continue;

      if (achievement.checkUnlocked(ctx)) {
        _unlocked[achievement.id] = AchievementUnlock(
          achievementId: achievement.id,
          unlockedAt: DateTime.now().millisecondsSinceEpoch,
        );
        _newlyUnlocked.add(achievement);
        _dirty = true;
        debugPrint('[Achievement] 解锁: ${achievement.title}');
      }
    }

    if (_dirty) save();
  }

  /// 判断某成就是否已解锁
  bool isUnlocked(String achievementId) => _unlocked.containsKey(achievementId);

  /// 获取解锁时间
  AchievementUnlock? getUnlock(String achievementId) =>
      _unlocked[achievementId];

  /// 获取当前进度上下文
  AchievementContext getContext() => _buildContext();

  /// 构建成就检查上下文
  AchievementContext _buildContext() {
    // 从 play_stats 获取播放次数数据
    final stats = rust_play_stats.getPlayStats();
    final totalPlayCount = stats.fold<int>(0, (sum, e) => sum + e.count);
    final distinctSongs = stats.length;
    final distinctArtists = stats.map((e) => e.artist).toSet().length;
    final maxSingleSongCount =
        stats.isEmpty ? 0 : stats.map((e) => e.count).reduce((a, b) => a > b ? a : b);

    // 从 listening calendar 获取时长/天数数据
    final calendar = ListeningCalendarService.instance;
    final totalDurationMinutes = calendar.totalDurationSeconds ~/ 60;
    final totalDays = calendar.totalDays;
    final currentStreak = calendar.currentStreak;
    final maxDailyMinutes = calendar.maxDailyDuration ~/ 60;
    final totalHours = calendar.totalDurationSeconds ~/ 3600;

    // 从播放历史判断特殊时刻
    final history = PlayHistoryService.instance.entries;
    bool hasLateNight = false;
    bool hasEarlyMorning = false;
    for (final entry in history) {
      final hour = entry.playedAtDateTime.hour;
      if (hour >= 0 && hour < 4) hasLateNight = true;
      if (hour >= 5 && hour < 7) hasEarlyMorning = true;
      if (hasLateNight && hasEarlyMorning) break;
    }

    return AchievementContext(
      totalPlayCount: totalPlayCount,
      totalDurationMinutes: totalDurationMinutes,
      totalDays: totalDays,
      currentStreak: currentStreak,
      distinctSongs: distinctSongs,
      distinctArtists: distinctArtists,
      maxDailyMinutes: maxDailyMinutes,
      hasLateNightPlay: hasLateNight,
      hasEarlyMorningPlay: hasEarlyMorning,
      maxSingleSongCount: maxSingleSongCount,
      totalHours: totalHours,
    );
  }

  /// 获取数据文件
  Future<File> _getFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory('${appDir.path}/.jmusic');
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    return File('${dataDir.path}/achievements.json');
  }
}
