import 'statistics_models.dart';

class HomeProgressSummary {
  const HomeProgressSummary({
    required this.streakDays,
    required this.totalSessions,
    required this.totalDurationSec,
    required this.latestActivity,
  });

  const HomeProgressSummary.empty()
    : streakDays = 0,
      totalSessions = 0,
      totalDurationSec = 0,
      latestActivity = null;

  factory HomeProgressSummary.fromOverview(OverviewStats overview) {
    return HomeProgressSummary(
      streakDays: overview.streakDays,
      totalSessions: overview.totalSessions,
      totalDurationSec: overview.totalDurationSec,
      latestActivity: overview.latestActivity,
    );
  }

  final int streakDays;
  final int totalSessions;
  final int totalDurationSec;
  final DateTime? latestActivity;

  bool get hasRecords => totalSessions > 0;
}
