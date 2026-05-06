import 'package:flutter/material.dart';

import '../core/statistics/learning_activity_catalog.dart';
import '../core/statistics/learning_activity_store.dart';
import '../core/statistics/statistics_aggregator.dart';
import '../core/statistics/statistics_models.dart';
import 'theme.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  final LearningActivityStore _store = LearningActivityStore.instance;

  StatisticsRange _selectedRange = StatisticsRange.last7Days;
  StatisticsSnapshot? _snapshot;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    final records = await _store.load();
    final snapshot = StatisticsAggregator.build(
      records: records,
      range: _selectedRange,
    );
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _loading = false;
    });
  }

  void _changeRange(StatisticsRange range) {
    if (_selectedRange == range) return;
    setState(() {
      _selectedRange = range;
      _loading = true;
    });
    _loadStatistics();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: AppTheme.backgroundLight,
              elevation: 0,
              title: const Text(
                'Statistics',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _loadStatistics,
                ),
              ],
            )
          : null,
      body: _loading || snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStatistics,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  widget.showAppBar ? 8 : 20,
                  16,
                  24,
                ),
                children: [
                  if (!widget.showAppBar) ...[
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Statistics',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          onPressed: _loadStatistics,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                  _OverviewCard(
                    overview: snapshot.overview,
                    selectedRange: _selectedRange,
                    onRangeSelected: _changeRange,
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle('분야별 통계'),
                  const SizedBox(height: 12),
                  ...snapshot.domainStats.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _DomainStatCard(item: item),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _SectionTitle('기능별 통계'),
                  const SizedBox(height: 12),
                  ...snapshot.featureStats.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _FeatureStatCard(item: item),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _SectionTitle('이번 주 집중 포인트'),
                  const SizedBox(height: 12),
                  _FocusInsightCard(item: snapshot.focusInsight),
                  const SizedBox(height: 20),
                  const _SectionTitle('최근 활동'),
                  const SizedBox(height: 12),
                  if (snapshot.recentActivities.isEmpty)
                    const _EmptyPanel(
                      message: '아직 기록이 없습니다. 첫 학습을 시작하면 최근 활동이 여기에 표시됩니다.',
                    )
                  else
                    ...snapshot.recentActivities.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RecentActivityTile(item: item),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.overview,
    required this.selectedRange,
    required this.onRangeSelected,
  });

  final OverviewStats overview;
  final StatisticsRange selectedRange;
  final ValueChanged<StatisticsRange> onRangeSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F4C81), Color(0xFF137FEC)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF137FEC).withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '한눈에 보는 학습 요약',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '학습량과 점수형 지표를 함께 확인하고 최근 흐름을 빠르게 점검할 수 있습니다.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Colors.white.withValues(alpha: 0.84),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: StatisticsRange.values.map((range) {
              return _RangeChip(
                key: ValueKey('stats_range_${range.name}'),
                label: range.label,
                selected: selectedRange == range,
                onTap: () => onRangeSelected(range),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryMetricCard(
                title: '연속 학습',
                value: '${overview.streakDays}일',
                valueKey: const ValueKey('overview_streak_value'),
              ),
              _SummaryMetricCard(
                title: '총 세션',
                value: '${overview.totalSessions}회',
                valueKey: const ValueKey('overview_sessions_value'),
              ),
              _SummaryMetricCard(
                title: '총 시간',
                value: _formatDuration(overview.totalDurationSec),
                valueKey: const ValueKey('overview_time_value'),
              ),
              _SummaryMetricCard(
                title: '최근 학습',
                value: _formatDate(overview.latestActivity),
                valueKey: const ValueKey('overview_latest_value'),
              ),
              _SummaryMetricCard(
                title: '평균 점수',
                value: overview.averageScorePercent == null
                    ? '기록 없음'
                    : '${overview.averageScorePercent}점',
                valueKey: const ValueKey('overview_average_score_value'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '최근 7일 학습량',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
                const SizedBox(height: 14),
                _WeeklyBarChart(bars: overview.weeklyBars),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day';
  }

  static String _formatDuration(int durationSec) {
    final hours = durationSec ~/ 3600;
    final minutes = (durationSec % 3600) ~/ 60;
    if (hours > 0) {
      return minutes > 0 ? '$hours시간 $minutes분' : '$hours시간';
    }
    if (minutes > 0) return '$minutes분';
    return '${durationSec.clamp(0, 59)}초';
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.18),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? AppTheme.textDark : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryMetricCard extends StatelessWidget {
  const _SummaryMetricCard({
    required this.title,
    required this.value,
    required this.valueKey,
  });

  final String title;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 152,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            key: valueKey,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyBarChart extends StatelessWidget {
  const _WeeklyBarChart({required this.bars});

  final List<WeeklyActivityBar> bars;

  @override
  Widget build(BuildContext context) {
    final maxValue = bars.fold<int>(
      0,
      (best, item) => item.value > best ? item.value : best,
    );
    return SizedBox(
      height: 132,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: bars.map((bar) {
          final ratio = maxValue == 0 ? 0.0 : bar.value / maxValue;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${bar.value}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.74),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 20,
                  height: 70 * (ratio == 0 ? 0.2 : ratio) + 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: ratio == 0 ? 0.18 : 0.92,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  bar.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: AppTheme.textDark,
      ),
    );
  }
}

class _DomainStatCard extends StatelessWidget {
  const _DomainStatCard({required this.item});

  final DomainStats item;

  @override
  Widget build(BuildContext context) {
    final spec = LearningActivityCatalog.domainById(item.domain);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: spec.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(spec.icon, color: spec.color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.sessionCount}세션 · 총 ${_formatDuration(item.totalDurationSec)} · 최근 ${_formatDate(item.latestActivity)}',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!item.hasScoreData)
            _StatusBadge(label: '점수 기반 통계 준비 중', color: spec.color)
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _InlineMetric(
                      label: '평균 점수',
                      value: '${item.averageScorePercent}점',
                      valueKey: ValueKey('domain_${item.domain}_average_score'),
                    ),
                    _InlineMetric(
                      label: '최고 점수',
                      value: '${item.bestScorePercent}점',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _MiniTrend(values: item.recentScorePercents, color: spec.color),
              ],
            ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day';
  }

  static String _formatDuration(int durationSec) {
    final hours = durationSec ~/ 3600;
    final minutes = (durationSec % 3600) ~/ 60;
    if (hours > 0) {
      return minutes > 0 ? '$hours시간 $minutes분' : '$hours시간';
    }
    if (minutes > 0) return '$minutes분';
    return '${durationSec.clamp(0, 59)}초';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({
    required this.label,
    required this.value,
    this.valueKey,
  });

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFD),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            key: valueKey,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTrend extends StatelessWidget {
  const _MiniTrend({required this.values, required this.color});

  final List<int> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safeValues = values.isEmpty ? const [0, 0, 0, 0, 0] : values;
    return Row(
      children: safeValues.map((value) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: double.infinity,
                  height: 10 + (value.clamp(0, 100) * 0.55),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: value == 0 ? 0.12 : 0.9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FeatureStatCard extends StatelessWidget {
  const _FeatureStatCard({required this.item});

  final FeatureStats item;

  @override
  Widget build(BuildContext context) {
    final spec = LearningActivityCatalog.featureById(item.featureId);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: spec.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(spec.icon, color: spec.color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '누적 ${item.usageCount}회 · 총 ${_formatDuration(item.totalDurationSec)} · 최근 ${_formatDate(item.latestActivity)}',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!item.hasRecords)
            _EmptyPanel(message: item.emptyMessage)
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: item.metrics
                  .map(
                    (metric) => Container(
                      constraints: const BoxConstraints(minWidth: 120),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5ECF4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            metric.label,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            metric.value,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day';
  }

  static String _formatDuration(int durationSec) {
    final hours = durationSec ~/ 3600;
    final minutes = (durationSec % 3600) ~/ 60;
    if (hours > 0) {
      return minutes > 0 ? '$hours시간 $minutes분' : '$hours시간';
    }
    if (minutes > 0) return '$minutes분';
    return '${durationSec.clamp(0, 59)}초';
  }
}

class _FocusInsightCard extends StatelessWidget {
  const _FocusInsightCard({required this.item});

  final StatisticsFocusInsight item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5E8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF4D6A8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '추천 학습 방향',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF9A6700),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            item.cta,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF9A6700),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentActivityTile extends StatelessWidget {
  const _RecentActivityTile({required this.item});

  final RecentActivityItem item;

  @override
  Widget build(BuildContext context) {
    final spec = LearningActivityCatalog.featureById(item.featureId);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: spec.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(spec.icon, color: spec.color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _formatDateTime(item.completedAt),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5ECF4)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 14,
          height: 1.5,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}
