import 'learning_activity_catalog.dart';
import 'learning_activity_record.dart';
import 'statistics_models.dart';

class StatisticsAggregator {
  const StatisticsAggregator._();

  static StatisticsSnapshot build({
    required List<LearningActivityRecord> records,
    required StatisticsRange range,
    DateTime? now,
  }) {
    final resolvedNow = now ?? DateTime.now();
    final filtered = _filterRecords(records, range, resolvedNow);
    final overview = _buildOverview(filtered, resolvedNow);
    final domains = _buildDomainStats(filtered);
    final features = _buildFeatureStats(filtered);
    final focus = _buildFocusInsight(
      allRecords: filtered,
      domains: domains,
      features: features,
      now: resolvedNow,
    );
    final recent = _buildRecentActivities(filtered);

    return StatisticsSnapshot(
      overview: overview,
      domainStats: domains,
      featureStats: features,
      focusInsight: focus,
      recentActivities: recent,
    );
  }

  static List<LearningActivityRecord> _filterRecords(
    List<LearningActivityRecord> records,
    StatisticsRange range,
    DateTime now,
  ) {
    final dayCount = range.dayCount;
    if (dayCount == null) {
      return List<LearningActivityRecord>.from(records)
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    }

    final cutoff = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: dayCount - 1));

    return records
        .where((record) => !record.completedAt.isBefore(cutoff))
        .toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  }

  static OverviewStats _buildOverview(
    List<LearningActivityRecord> records,
    DateTime now,
  ) {
    return OverviewStats(
      streakDays: _calculateStreak(records, now),
      totalSessions: records.length,
      totalDurationSec: records.fold<int>(
        0,
        (sum, item) => sum + item.durationSec,
      ),
      latestActivity: records.isEmpty ? null : records.first.completedAt,
      averageScorePercent: _averageScorePercent(records),
      weeklyBars: _buildWeeklyBars(records, now),
    );
  }

  static List<DomainStats> _buildDomainStats(
    List<LearningActivityRecord> records,
  ) {
    return LearningActivityCatalog.domainSpecs.map((spec) {
      final domainRecords =
          records.where((record) => record.domain == spec.domain).toList()
            ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
      final scored = domainRecords.where(_hasScore).toList();

      return DomainStats(
        domain: spec.domain,
        title: spec.title,
        sessionCount: domainRecords.length,
        totalDurationSec: domainRecords.fold<int>(
          0,
          (sum, item) => sum + item.durationSec,
        ),
        latestActivity: domainRecords.isEmpty
            ? null
            : domainRecords.first.completedAt,
        averageScorePercent: _averageScorePercent(scored),
        bestScorePercent: _bestScorePercent(scored),
        recentScorePercents: _recentScorePercents(scored),
      );
    }).toList();
  }

  static List<FeatureStats> _buildFeatureStats(
    List<LearningActivityRecord> records,
  ) {
    return LearningActivityCatalog.featureSpecs.map((spec) {
      final featureRecords =
          records.where((record) => record.featureId == spec.featureId).toList()
            ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
      final scored = featureRecords.where(_hasScore).toList();

      return FeatureStats(
        featureId: spec.featureId,
        title: spec.title,
        domain: spec.domain,
        usageCount: featureRecords.length,
        totalDurationSec: featureRecords.fold<int>(
          0,
          (sum, item) => sum + item.durationSec,
        ),
        latestActivity: featureRecords.isEmpty
            ? null
            : featureRecords.first.completedAt,
        averageScorePercent: _averageScorePercent(scored),
        bestScorePercent: _bestScorePercent(scored),
        recentScorePercents: _recentScorePercents(scored),
        metrics: _buildFeatureMetrics(spec.featureId, featureRecords),
        emptyMessage: spec.emptyMessage,
      );
    }).toList();
  }

  static List<StatisticMetric> _buildFeatureMetrics(
    String featureId,
    List<LearningActivityRecord> records,
  ) {
    switch (featureId) {
      case LearningFeatureIds.aiTutorChat:
        final totalTurns = records.fold<int>(
          0,
          (sum, item) => sum + _metadataInt(item.metadata, 'turnCount'),
        );
        return <StatisticMetric>[
          StatisticMetric(label: '대화 세션', value: '${records.length}회'),
          StatisticMetric(label: '총 턴 수', value: '$totalTurns턴'),
          StatisticMetric(
            label: '평균 턴 수',
            value: records.isEmpty
                ? '-'
                : '${_formatDecimal(totalTurns / records.length)}턴',
          ),
        ];
      case LearningFeatureIds.aiFreeTalk:
        final dimensionAverages = _averageSpeakingDimensions(records);
        return <StatisticMetric>[
          StatisticMetric(
            label: '평균 총점',
            value: _formatScore(_averageScorePercent(records)),
          ),
          StatisticMetric(
            label: '최고 총점',
            value: _formatScore(_bestScorePercent(records)),
          ),
          StatisticMetric(
            label: '최근 총점',
            value: _formatScore(
              records.isEmpty ? null : _scorePercent(records.first),
            ),
          ),
          for (final entry in dimensionAverages.entries)
            StatisticMetric(label: entry.key, value: '${entry.value}%'),
        ];
      case LearningFeatureIds.vocabStudy:
        final totalWords = records.fold<int>(
          0,
          (sum, item) =>
              sum +
              (item.attemptCount ?? _metadataInt(item.metadata, 'wordCount')),
        );
        return <StatisticMetric>[
          StatisticMetric(label: '학습한 단어', value: '$totalWords개'),
          StatisticMetric(label: '복습 세션', value: '${records.length}회'),
          StatisticMetric(label: '완료한 세트', value: '${records.length}세트'),
        ];
      case LearningFeatureIds.vocabQuiz:
        final totalAttempts = records.fold<int>(
          0,
          (sum, item) => sum + (item.attemptCount ?? 0),
        );
        final totalCorrect = records.fold<int>(
          0,
          (sum, item) => sum + (item.correctCount ?? 0),
        );
        final bestAccuracy = records.fold<int>(
          0,
          (best, item) =>
              _accuracyPercent(item) > best ? _accuracyPercent(item) : best,
        );
        final averageAccuracy = totalAttempts == 0
            ? null
            : ((totalCorrect / totalAttempts) * 100).round();
        return <StatisticMetric>[
          StatisticMetric(
            label: '평균 정답률',
            value: averageAccuracy == null ? '-' : '$averageAccuracy%',
          ),
          StatisticMetric(
            label: '최고 정답률',
            value: records.isEmpty ? '-' : '$bestAccuracy%',
          ),
          StatisticMetric(label: '총 문제 수', value: '$totalAttempts문제'),
          StatisticMetric(label: '맞힌 문제 수', value: '$totalCorrect문제'),
        ];
      case LearningFeatureIds.roleplay:
        final completedCount = records
            .where((item) => item.metadata['completed'] == true)
            .length;
        final scenarioCounts = <String, int>{};
        for (final item in records) {
          final title = (item.metadata['scenarioTitle'] ?? '').toString();
          if (title.isEmpty) continue;
          scenarioCounts[title] = (scenarioCounts[title] ?? 0) + 1;
        }
        var topScenario = '-';
        var topCount = 0;
        scenarioCounts.forEach((title, count) {
          if (count > topCount) {
            topScenario = title;
            topCount = count;
          }
        });
        final completionRate = records.isEmpty
            ? null
            : ((completedCount / records.length) * 100).round();
        return <StatisticMetric>[
          StatisticMetric(label: '시작 세션', value: '${records.length}회'),
          StatisticMetric(label: '완료 세션', value: '$completedCount회'),
          StatisticMetric(
            label: '완료율',
            value: completionRate == null ? '-' : '$completionRate%',
          ),
          StatisticMetric(label: '자주 연습한 시나리오', value: topScenario),
        ];
      case LearningFeatureIds.toeicWriting:
        final taskBuckets = <String, List<int>>{
          '사진 묘사': <int>[],
          '이메일 응답': <int>[],
          '의견 에세이': <int>[],
        };
        for (final item in records) {
          final label = (item.metadata['taskTypeLabel'] ?? '').toString();
          final score = _scorePercent(item);
          if (label.isEmpty || score == null) continue;
          taskBuckets.putIfAbsent(label, () => <int>[]).add(score);
        }
        return <StatisticMetric>[
          StatisticMetric(
            label: '평균 총점',
            value: _formatScore(_averageScorePercent(records)),
          ),
          StatisticMetric(
            label: '최고 총점',
            value: _formatScore(_bestScorePercent(records)),
          ),
          for (final entry in taskBuckets.entries)
            StatisticMetric(
              label: entry.key,
              value: entry.value.isEmpty
                  ? '0회'
                  : '${entry.value.length}회 · ${_averageInts(entry.value)}점',
            ),
        ];
      case LearningFeatureIds.grammarCheck:
        final totalErrors = records.fold<int>(
          0,
          (sum, item) => sum + _metadataInt(item.metadata, 'errorCount'),
        );
        final totalSuggestions = records.fold<int>(
          0,
          (sum, item) => sum + _metadataInt(item.metadata, 'suggestionCount'),
        );
        return <StatisticMetric>[
          StatisticMetric(label: '검사 횟수', value: '${records.length}회'),
          StatisticMetric(label: '발견한 오류', value: '$totalErrors개'),
          StatisticMetric(label: '수정 제안', value: '$totalSuggestions개'),
        ];
      case LearningFeatureIds.toneConversion:
        final toneCounts = <String, int>{};
        for (final item in records) {
          final tone = _toneLabel((item.metadata['tone'] ?? '').toString());
          toneCounts[tone] = (toneCounts[tone] ?? 0) + 1;
        }
        final sorted = toneCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topTone = sorted.isEmpty ? '-' : sorted.first.key;
        final ratioText = sorted.isEmpty
            ? '-'
            : sorted
                  .map(
                    (entry) =>
                        '${entry.key} ${((entry.value / records.length) * 100).round()}%',
                  )
                  .join(' · ');
        return <StatisticMetric>[
          StatisticMetric(label: '변환 횟수', value: '${records.length}회'),
          StatisticMetric(label: '가장 많이 쓴 톤', value: topTone),
          StatisticMetric(label: '톤 사용 비율', value: ratioText),
        ];
      default:
        return const <StatisticMetric>[];
    }
  }

  static StatisticsFocusInsight _buildFocusInsight({
    required List<LearningActivityRecord> allRecords,
    required List<DomainStats> domains,
    required List<FeatureStats> features,
    required DateTime now,
  }) {
    final weeklyRecords = _filterRecords(
      allRecords,
      StatisticsRange.last7Days,
      now,
    );
    if (weeklyRecords.isEmpty) {
      return const StatisticsFocusInsight(
        title: '아직 학습 기록이 없습니다',
        description: '첫 학습을 완료하면 약점과 추천 학습 포인트를 여기에 정리해 드립니다.',
        cta: 'Study 화면에서 원하는 기능을 하나 시작해 보세요.',
      );
    }

    final weeklyDomainStats = _buildDomainStats(weeklyRecords)
      ..sort((a, b) {
        final aScore = a.averageScorePercent ?? 101;
        final bScore = b.averageScorePercent ?? 101;
        return aScore.compareTo(bScore);
      });
    final weakestDomain = weeklyDomainStats.firstWhere(
      (item) => item.averageScorePercent != null,
      orElse: () => const DomainStats(
        domain: '',
        title: '',
        sessionCount: 0,
        totalDurationSec: 0,
        latestActivity: null,
        averageScorePercent: null,
        bestScorePercent: null,
        recentScorePercents: <int>[],
      ),
    );

    if (weakestDomain.averageScorePercent != null) {
      return StatisticsFocusInsight(
        title: '${weakestDomain.title} 분야를 먼저 끌어올려 보세요',
        description: _focusDescriptionForDomain(weakestDomain.domain),
        cta: _focusCtaForDomain(weakestDomain.domain),
      );
    }

    final sortedFeatures = List<FeatureStats>.from(features)
      ..sort((a, b) {
        final countCompare = a.usageCount.compareTo(b.usageCount);
        if (countCompare != 0) return countCompare;
        return LearningFeatureIds.ordered
            .indexOf(a.featureId)
            .compareTo(LearningFeatureIds.ordered.indexOf(b.featureId));
      });
    final leastUsed = sortedFeatures.first;
    return StatisticsFocusInsight(
      title: '${leastUsed.title} 연습을 조금 더 늘려 보세요',
      description:
          '최근 7일 기준으로 다른 기능보다 사용 빈도가 낮습니다. 균형 있게 학습하면 전체 리듬을 유지하기 좋습니다.',
      cta: '${leastUsed.title}에서 짧게 한 세션만 더 진행해 보세요.',
    );
  }

  static List<RecentActivityItem> _buildRecentActivities(
    List<LearningActivityRecord> records,
  ) {
    return records.take(5).map((record) {
      final feature = LearningActivityCatalog.featureById(record.featureId);
      return RecentActivityItem(
        featureId: record.featureId,
        title: feature.title,
        subtitle: _recentSubtitle(record),
        completedAt: record.completedAt,
      );
    }).toList();
  }

  static int _calculateStreak(
    List<LearningActivityRecord> records,
    DateTime now,
  ) {
    if (records.isEmpty) return 0;
    final dates = records
        .map(
          (item) => DateTime(
            item.completedAt.year,
            item.completedAt.month,
            item.completedAt.day,
          ),
        )
        .toSet();
    var streak = 0;
    var cursor = DateTime(now.year, now.month, now.day);
    while (dates.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static List<WeeklyActivityBar> _buildWeeklyBars(
    List<LearningActivityRecord> records,
    DateTime now,
  ) {
    final sessionByDay = <DateTime, int>{};
    for (final record in records) {
      final key = DateTime(
        record.completedAt.year,
        record.completedAt.month,
        record.completedAt.day,
      );
      sessionByDay[key] = (sessionByDay[key] ?? 0) + 1;
    }

    return List<WeeklyActivityBar>.generate(7, (index) {
      final date = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 6 - index));
      return WeeklyActivityBar(
        label: _weekdayLabel(date.weekday),
        value: sessionByDay[date] ?? 0,
      );
    });
  }

  static int? _averageScorePercent(List<LearningActivityRecord> records) {
    final scores = records.map(_scorePercent).whereType<int>().toList();
    if (scores.isEmpty) return null;
    return _averageInts(scores);
  }

  static int? _bestScorePercent(List<LearningActivityRecord> records) {
    final scores = records.map(_scorePercent).whereType<int>().toList();
    if (scores.isEmpty) return null;
    return scores.reduce((a, b) => a > b ? a : b);
  }

  static List<int> _recentScorePercents(List<LearningActivityRecord> records) {
    final scored = records.where(_hasScore).toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return scored
        .take(5)
        .toList()
        .reversed
        .map((item) => _scorePercent(item) ?? 0)
        .toList();
  }

  static Map<String, int> _averageSpeakingDimensions(
    List<LearningActivityRecord> records,
  ) {
    const labels = <String, String>{
      'task_fulfillment_interaction': '상호작용',
      'pronunciation_delivery': '발음',
      'fluency': '유창성',
      'grammar_control': '문법',
      'vocabulary_expression': '어휘',
    };
    final totals = <String, int>{};
    final counts = <String, int>{};

    for (final record in records) {
      final dimensionScores = record.metadata['dimensionScores'];
      if (dimensionScores is! Map) continue;
      for (final entry in dimensionScores.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final score = _metadataInt(Map<String, dynamic>.from(value), 'score');
        final max = _metadataInt(Map<String, dynamic>.from(value), 'max');
        if (max <= 0) continue;
        final percent = ((score / max) * 100).round();
        totals[entry.key.toString()] =
            (totals[entry.key.toString()] ?? 0) + percent;
        counts[entry.key.toString()] = (counts[entry.key.toString()] ?? 0) + 1;
      }
    }

    return <String, int>{
      for (final key in labels.keys)
        labels[key]!: counts[key] == null || counts[key] == 0
            ? 0
            : (totals[key]! / counts[key]!).round(),
    };
  }

  static bool _hasScore(LearningActivityRecord record) {
    return record.score != null &&
        record.scoreMax != null &&
        (record.scoreMax ?? 0) > 0;
  }

  static int? _scorePercent(LearningActivityRecord record) {
    if (!_hasScore(record)) return null;
    return ((record.score! / record.scoreMax!) * 100).round();
  }

  static int _accuracyPercent(LearningActivityRecord record) {
    final attempts = record.attemptCount ?? 0;
    if (attempts <= 0) return 0;
    return (((record.correctCount ?? 0) / attempts) * 100).round();
  }

  static int _averageInts(List<int> values) {
    if (values.isEmpty) return 0;
    final total = values.fold<int>(0, (sum, item) => sum + item);
    return (total / values.length).round();
  }

  static int _metadataInt(Map<String, dynamic> metadata, String key) {
    final value = metadata[key];
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _formatScore(int? value) {
    if (value == null) return '-';
    return '$value점';
  }

  static String _formatDecimal(double value) {
    final rounded = value.toStringAsFixed(1);
    if (rounded.endsWith('.0')) {
      return rounded.substring(0, rounded.length - 2);
    }
    return rounded;
  }

  static String _toneLabel(String tone) {
    switch (tone) {
      case 'formal':
        return 'Formal';
      case 'polite':
        return 'Polite';
      case 'friendly':
        return 'Friendly';
      case 'concise':
        return 'Concise';
      default:
        return tone.isEmpty ? '-' : tone;
    }
  }

  static String _weekdayLabel(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return '월';
      case DateTime.tuesday:
        return '화';
      case DateTime.wednesday:
        return '수';
      case DateTime.thursday:
        return '목';
      case DateTime.friday:
        return '금';
      case DateTime.saturday:
        return '토';
      case DateTime.sunday:
      default:
        return '일';
    }
  }

  static String _recentSubtitle(LearningActivityRecord record) {
    switch (record.featureId) {
      case LearningFeatureIds.aiTutorChat:
        return '${_metadataInt(record.metadata, 'turnCount')}턴 · ${_formatDuration(record.durationSec)}';
      case LearningFeatureIds.aiFreeTalk:
        return '${_formatDuration(record.durationSec)} · ${record.metadata['gradeLabel'] ?? _formatScore(_scorePercent(record))}';
      case LearningFeatureIds.vocabStudy:
        return '${record.attemptCount ?? _metadataInt(record.metadata, 'wordCount')}개 단어 암기';
      case LearningFeatureIds.vocabQuiz:
        return '정답률 ${_accuracyPercent(record)}%';
      case LearningFeatureIds.roleplay:
        return '${record.metadata['scenarioTitle'] ?? '시나리오'} · ${record.metadata['completed'] == true ? '완료' : '진행 종료'}';
      case LearningFeatureIds.toeicWriting:
        return '${record.metadata['taskTypeLabel'] ?? '유형'} · ${_formatScore(_scorePercent(record))}';
      case LearningFeatureIds.grammarCheck:
        return '오류 ${_metadataInt(record.metadata, 'errorCount')}개 · 제안 ${_metadataInt(record.metadata, 'suggestionCount')}개';
      case LearningFeatureIds.toneConversion:
        return '${_toneLabel((record.metadata['tone'] ?? '').toString())} 톤으로 변환';
      default:
        return _formatDuration(record.durationSec);
    }
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

  static String _focusDescriptionForDomain(String domain) {
    switch (domain) {
      case LearningDomains.speaking:
        return '프리토킹에서 한 문장씩 조금 더 길게 이어 말하고, 자주 쓰는 연결 표현을 반복하면 점수 향상에 가장 직접적입니다.';
      case LearningDomains.writing:
        return '라이팅에서는 약한 유형을 다시 풀고, 피드백에서 지적된 포인트를 같은 날 한 번 더 반영해 보는 것이 가장 효율적입니다.';
      default:
        return '가장 낮게 나온 분야를 중심으로 짧게 한 세션만 더 진행해도 전체 평균을 끌어올리는 데 도움이 됩니다.';
    }
  }

  static String _focusCtaForDomain(String domain) {
    switch (domain) {
      case LearningDomains.speaking:
        return 'AI 프리토킹에서 5분만 더 말해 보세요.';
      case LearningDomains.writing:
        return 'TOEIC Writing에서 가장 약한 유형을 다시 풀어 보세요.';
      default:
        return '해당 분야에서 한 세션 더 진행해 보세요.';
    }
  }
}
