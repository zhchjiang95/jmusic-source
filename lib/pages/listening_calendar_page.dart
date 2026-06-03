import 'package:flutter/material.dart';
import 'package:jmusic/services/listening_calendar_service.dart';

/// 听歌打卡日历页面 — GitHub 贡献图风格
class ListeningCalendarPage extends StatefulWidget {
  const ListeningCalendarPage({super.key});

  @override
  State<ListeningCalendarPage> createState() => _ListeningCalendarPageState();
}

class _ListeningCalendarPageState extends State<ListeningCalendarPage> {
  final _service = ListeningCalendarService.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _service.load();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          '听歌日历',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatsCards(theme),
                  const SizedBox(height: 24),
                  _buildCalendarGraph(theme),
                  const SizedBox(height: 24),
                  _buildLegend(theme),
                  const SizedBox(height: 24),
                  _buildRecentDays(theme),
                ],
              ),
            ),
    );
  }

  /// 顶部统计卡片
  Widget _buildStatsCards(ThemeData theme) {
    final todayRecord = _service.todayRecord;
    final todayMinutes = (todayRecord?.durationSeconds ?? 0) ~/ 60;
    final totalHours = _service.totalDurationSeconds ~/ 3600;
    final totalDays = _service.totalDays;
    final streak = _service.currentStreak;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.timer_outlined,
            label: '今日',
            value: todayMinutes > 0 ? '$todayMinutes 分钟' : '0 分钟',
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.local_fire_department_outlined,
            label: '连续',
            value: '$streak 天',
            color: Colors.orangeAccent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.calendar_month_outlined,
            label: '累计',
            value: '$totalDays 天',
            color: Colors.greenAccent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.headphones_outlined,
            label: '总时长',
            value: '$totalHours 小时',
            color: Colors.blueAccent,
          ),
        ),
      ],
    );
  }

  /// GitHub 贡献图风格日历
  Widget _buildCalendarGraph(ThemeData theme) {
    // 显示最近 16 周 (112 天)
    const weeksToShow = 16;

    final today = DateTime.now();
    final maxDuration = _service.maxDailyDuration;

    // 计算起始日期（让今天在最后一列的正确行）
    final todayWeekday = today.weekday; // 1=周一, 7=周日
    final startDate = today.subtract(Duration(days: (weeksToShow - 1) * 7 + (todayWeekday - 1)));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.grid_view_rounded,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '最近 $weeksToShow 周听歌热力图',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 星期标签
              _buildWeekdayLabels(theme),
              const SizedBox(width: 4),
              // 热力图格子
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 月份标签在格子上方
                    _buildMonthLabelsAdaptive(startDate, weeksToShow, theme),
                    const SizedBox(height: 4),
                    _buildHeatmapGrid(
                      startDate,
                      today,
                      weeksToShow,
                      maxDuration,
                      theme,
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

  /// 月份标签（自适应宽度，使用 LayoutBuilder 对齐格子列）
  Widget _buildMonthLabelsAdaptive(DateTime startDate, int weeks, ThemeData theme) {
    const monthNames = [
      '', '1月', '2月', '3月', '4月', '5月', '6月',
      '7月', '8月', '9月', '10月', '11月', '12月',
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final spacing = 3.0;
        final cellSize = ((availableWidth - (weeks - 1) * spacing) / weeks)
            .clamp(8.0, 14.0);
        final colWidth = cellSize + spacing;

        final labels = <Widget>[];
        int lastMonth = -1;

        for (int w = 0; w < weeks; w++) {
          final weekStart = startDate.add(Duration(days: w * 7));
          final month = weekStart.month;
          if (month != lastMonth) {
            labels.add(
              Positioned(
                left: w * colWidth,
                child: Text(
                  monthNames[month],
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                  ),
                ),
              ),
            );
            lastMonth = month;
          }
        }

        return SizedBox(
          height: 14,
          width: availableWidth,
          child: Stack(children: labels),
        );
      },
    );
  }

  /// 星期标签列（高度与格子对齐）
  Widget _buildWeekdayLabels(ThemeData theme) {
    const days = ['一', '', '三', '', '五', '', '日'];
    // 格子高度 + 间距需要对齐，这里用固定间距
    return Padding(
      padding: const EdgeInsets.only(top: 18), // 与月份标签行对齐
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(7, (i) {
          return SizedBox(
            height: 14 + 3, // cellSize(~14) + spacing(3)
            child: days[i].isNotEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      days[i],
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 10,
                      ),
                    ),
                  )
                : null,
          );
        }),
      ),
    );
  }

  /// 热力图格子网格
  Widget _buildHeatmapGrid(
    DateTime startDate,
    DateTime today,
    int weeks,
    int maxDuration,
    ThemeData theme,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final spacing = 3.0;
        final cellSize = ((availableWidth - (weeks - 1) * spacing) / weeks)
            .clamp(8.0, 14.0);

        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(weeks, (col) {
            return Padding(
              padding: EdgeInsets.only(right: col < weeks - 1 ? spacing : 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(7, (row) {
                  final date = startDate.add(Duration(days: col * 7 + row));
                  final dateKey = ListeningCalendarService.dateKey(date);
                  final record = _service.getRecord(dateKey);

                  // 未来的日期显示为空占位
                  if (date.isAfter(today)) {
                    return Padding(
                      padding: EdgeInsets.only(bottom: row < 6 ? spacing : 0),
                      child: SizedBox(width: cellSize, height: cellSize),
                    );
                  }

                  final duration = record?.durationSeconds ?? 0;
                  final level = _getIntensityLevel(duration, maxDuration);
                  final color = _getLevelColor(level, theme);

                  return Padding(
                    padding: EdgeInsets.only(bottom: row < 6 ? spacing : 0),
                    child: Tooltip(
                      message: _buildTooltip(date, record),
                      child: Container(
                        width: cellSize,
                        height: cellSize,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        );
      },
    );
  }

  /// 图例
  Widget _buildLegend(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '少',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 6),
        for (int i = 0; i <= 4; i++) ...[
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: _getLevelColor(i, theme),
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
        ],
        const SizedBox(width: 3),
        Text(
          '多',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  /// 最近 7 天详情
  Widget _buildRecentDays(ThemeData theme) {
    final records = _service.getRecentDays(7);
    final today = DateTime.now();
    const weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '最近 7 天',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...List.generate(7, (i) {
            final date = today.subtract(Duration(days: 6 - i));
            final record = records[i];
            final minutes = (record?.durationSeconds ?? 0) ~/ 60;
            final count = record?.playCount ?? 0;
            final isToday = i == 6;
            final weekday = weekdayNames[date.weekday - 1];
            final dateStr =
                '${date.month}/${date.day}';

            // 计算条形图宽度
            final maxMin = records
                .where((r) => r != null)
                .map((r) => r!.durationSeconds ~/ 60)
                .fold(1, (a, b) => a > b ? a : b);
            final barRatio = maxMin > 0 ? (minutes / maxMin).clamp(0.0, 1.0) : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  // 日期
                  SizedBox(
                    width: 65,
                    child: Text(
                      isToday ? '今天' : '$weekday $dateStr',
                      style: TextStyle(
                        color: isToday
                            ? theme.colorScheme.primary
                            : Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                        fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  // 条形图
                  Expanded(
                    child: Container(
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: barRatio,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.primary.withValues(alpha: 0.7),
                                theme.colorScheme.primary,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 时长
                  SizedBox(
                    width: 55,
                    child: Text(
                      minutes > 0 ? '$minutes 分钟' : '-',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: minutes > 0
                            ? Colors.white.withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.25),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 次数
                  SizedBox(
                    width: 35,
                    child: Text(
                      count > 0 ? '$count首' : '',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 计算强度等级 (0-4)
  int _getIntensityLevel(int durationSeconds, int maxDuration) {
    if (durationSeconds == 0) return 0;
    if (maxDuration == 0) return 1;

    // 使用分钟阈值而非纯比例，更符合直觉
    final minutes = durationSeconds ~/ 60;
    if (minutes >= 60) return 4; // 1小时+
    if (minutes >= 30) return 3; // 30分钟+
    if (minutes >= 15) return 2; // 15分钟+
    return 1; // >0 分钟
  }

  /// 获取等级对应颜色
  Color _getLevelColor(int level, ThemeData theme) {
    switch (level) {
      case 0:
        return Colors.white.withValues(alpha: 0.06);
      case 1:
        return theme.colorScheme.primary.withValues(alpha: 0.25);
      case 2:
        return theme.colorScheme.primary.withValues(alpha: 0.5);
      case 3:
        return theme.colorScheme.primary.withValues(alpha: 0.75);
      case 4:
        return theme.colorScheme.primary;
      default:
        return Colors.white.withValues(alpha: 0.06);
    }
  }

  /// 构建 tooltip 文本
  String _buildTooltip(DateTime date, DailyListeningRecord? record) {
    final dateStr =
        '${date.year}/${date.month}/${date.day}';
    if (record == null || record.durationSeconds == 0) {
      return '$dateStr\n无听歌记录';
    }
    final minutes = record.durationSeconds ~/ 60;
    final hours = minutes ~/ 60;
    final remainMin = minutes % 60;
    final timeStr = hours > 0 ? '$hours小时$remainMin分钟' : '$minutes分钟';
    return '$dateStr\n听歌 $timeStr\n播放 ${record.playCount} 首';
  }
}

/// 统计卡片组件
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
