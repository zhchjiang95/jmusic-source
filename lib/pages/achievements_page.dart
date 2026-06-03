import 'package:flutter/material.dart';
import 'package:jmusic/services/achievement_service.dart';

/// 成就系统页面
class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  final _service = AchievementService.instance;
  late AchievementContext _ctx;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _service.load();
    _ctx = _service.getContext();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          '听歌成就',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_service.unlockedCount}/${_service.totalCount}',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(theme),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final categories = AchievementCategory.values;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 进度总览
          _buildOverview(theme),
          const SizedBox(height: 20),
          // 按类别展示
          for (final category in categories) ...[
            _buildCategorySection(category, theme),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  /// 总览卡片
  Widget _buildOverview(ThemeData theme) {
    final unlocked = _service.unlockedCount;
    final total = _service.totalCount;
    final progress = total > 0 ? unlocked / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.15),
            theme.colorScheme.tertiary.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // 圆形进度
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 5,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      color: theme.colorScheme.primary,
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '已解锁 $unlocked / $total 个成就',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getMotivation(progress),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 类别区域
  Widget _buildCategorySection(AchievementCategory category, ThemeData theme) {
    final achievements = AchievementService.allAchievements
        .where((a) => a.category == category)
        .toList();

    if (achievements.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            _categoryName(category),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...achievements.map((a) => _buildAchievementTile(a, theme)),
      ],
    );
  }

  /// 单个成就 Tile
  Widget _buildAchievementTile(Achievement achievement, ThemeData theme) {
    final unlocked = _service.isUnlocked(achievement.id);
    final unlock = _service.getUnlock(achievement.id);
    final progress = achievement.getProgress?.call(_ctx);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: unlocked
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: unlocked
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // 图标
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: unlocked
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              unlocked ? achievement.icon : '🔒',
              style: TextStyle(
                fontSize: unlocked ? 20 : 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        achievement.title,
                        style: TextStyle(
                          color: unlocked ? Colors.white : Colors.white54,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _buildRarityBadge(achievement.rarity, theme),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  achievement.description,
                  style: TextStyle(
                    color: unlocked
                        ? Colors.white.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.3),
                    fontSize: 11,
                  ),
                ),
                // 进度条
                if (!unlocked && progress != null) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ],
                // 解锁时间
                if (unlocked && unlock != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${unlock.unlockedDateTime.year}/${unlock.unlockedDateTime.month}/${unlock.unlockedDateTime.day} 解锁',
                    style: TextStyle(
                      color: theme.colorScheme.primary.withValues(alpha: 0.6),
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 稀有度标签
  Widget _buildRarityBadge(AchievementRarity rarity, ThemeData theme) {
    final (label, color) = switch (rarity) {
      AchievementRarity.common => ('普通', Colors.grey),
      AchievementRarity.rare => ('稀有', Colors.blueAccent),
      AchievementRarity.epic => ('史诗', Colors.purpleAccent),
      AchievementRarity.legendary => ('传说', Colors.amber),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _categoryName(AchievementCategory category) {
    return switch (category) {
      AchievementCategory.duration => '⏱️ 听歌时长',
      AchievementCategory.playCount => '🎵 播放次数',
      AchievementCategory.streak => '🔥 连续打卡',
      AchievementCategory.exploration => '🗺️ 探索发现',
      AchievementCategory.moment => '✨ 特殊时刻',
    };
  }

  String _getMotivation(double progress) {
    if (progress >= 1.0) return '全部解锁！你是终极乐迷！';
    if (progress >= 0.75) return '即将全部解锁，再接再厉！';
    if (progress >= 0.5) return '已经过半，继续保持！';
    if (progress >= 0.25) return '进展不错，继续听歌！';
    return '开始你的音乐之旅吧！';
  }
}
