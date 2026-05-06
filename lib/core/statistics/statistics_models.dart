enum StatisticsRange { last7Days, last30Days, all }

extension StatisticsRangeX on StatisticsRange {
  String get label => switch (this) {
    StatisticsRange.last7Days => '7일',
    StatisticsRange.last30Days => '30일',
    StatisticsRange.all => '전체',
  };

  int? get dayCount => switch (this) {
    StatisticsRange.last7Days => 7,
    StatisticsRange.last30Days => 30,
    StatisticsRange.all => null,
  };
}

class WeeklyActivityBar {
  const WeeklyActivityBar({required this.label, required this.value});

  final String label;
  final int value;
}

class StatisticMetric {
  const StatisticMetric({required this.label, required this.value});

  final String label;
  final String value;
}

class OverviewStats {
  const OverviewStats({
    required this.streakDays,
    required this.totalSessions,
    required this.totalDurationSec,
    required this.latestActivity,
    required this.averageScorePercent,
    required this.weeklyBars,
  });

  final int streakDays;
  final int totalSessions;
  final int totalDurationSec;
  final DateTime? latestActivity;
  final int? averageScorePercent;
  final List<WeeklyActivityBar> weeklyBars;
}

class DomainStats {
  const DomainStats({
    required this.domain,
    required this.title,
    required this.sessionCount,
    required this.totalDurationSec,
    required this.latestActivity,
    required this.averageScorePercent,
    required this.bestScorePercent,
    required this.recentScorePercents,
  });

  final String domain;
  final String title;
  final int sessionCount;
  final int totalDurationSec;
  final DateTime? latestActivity;
  final int? averageScorePercent;
  final int? bestScorePercent;
  final List<int> recentScorePercents;

  bool get hasScoreData => averageScorePercent != null;
}

class FeatureStats {
  const FeatureStats({
    required this.featureId,
    required this.title,
    required this.domain,
    required this.usageCount,
    required this.totalDurationSec,
    required this.latestActivity,
    required this.averageScorePercent,
    required this.bestScorePercent,
    required this.recentScorePercents,
    required this.metrics,
    required this.emptyMessage,
  });

  final String featureId;
  final String title;
  final String domain;
  final int usageCount;
  final int totalDurationSec;
  final DateTime? latestActivity;
  final int? averageScorePercent;
  final int? bestScorePercent;
  final List<int> recentScorePercents;
  final List<StatisticMetric> metrics;
  final String emptyMessage;

  bool get hasRecords => usageCount > 0;
}

class RecentActivityItem {
  const RecentActivityItem({
    required this.featureId,
    required this.title,
    required this.subtitle,
    required this.completedAt,
  });

  final String featureId;
  final String title;
  final String subtitle;
  final DateTime completedAt;
}

class StatisticsFocusInsight {
  const StatisticsFocusInsight({
    required this.title,
    required this.description,
    required this.cta,
  });

  final String title;
  final String description;
  final String cta;
}

class StatisticsSnapshot {
  const StatisticsSnapshot({
    required this.overview,
    required this.domainStats,
    required this.featureStats,
    required this.focusInsight,
    required this.recentActivities,
  });

  final OverviewStats overview;
  final List<DomainStats> domainStats;
  final List<FeatureStats> featureStats;
  final StatisticsFocusInsight focusInsight;
  final List<RecentActivityItem> recentActivities;
}
