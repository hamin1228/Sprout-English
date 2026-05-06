import 'package:english_ai/core/statistics/learning_activity_record.dart';
import 'package:english_ai/core/statistics/statistics_aggregator.dart';
import 'package:english_ai/core/statistics/statistics_models.dart';
import 'package:flutter_test/flutter_test.dart';

StatisticMetric _metricByLabel(
  Iterable<StatisticMetric> metrics,
  String label,
) {
  return metrics.firstWhere((metric) => metric.label == label);
}

LearningActivityRecord _record({
  required String featureId,
  required String domain,
  required DateTime completedAt,
  int durationSec = 300,
  int? score,
  int? scoreMax,
  int? attemptCount,
  int? correctCount,
  Map<String, dynamic> metadata = const <String, dynamic>{},
}) {
  return LearningActivityRecord(
    featureId: featureId,
    domain: domain,
    completedAt: completedAt,
    durationSec: durationSec,
    score: score,
    scoreMax: scoreMax,
    attemptCount: attemptCount,
    correctCount: correctCount,
    metadata: metadata,
  );
}

void main() {
  final now = DateTime(2026, 3, 29, 12);

  test('empty records still expose all sections and feature shells', () {
    final snapshot = StatisticsAggregator.build(
      records: const <LearningActivityRecord>[],
      range: StatisticsRange.last7Days,
      now: now,
    );

    expect(snapshot.overview.totalSessions, 0);
    expect(snapshot.domainStats.length, 4);
    expect(snapshot.featureStats.length, 8);
    expect(snapshot.recentActivities, isEmpty);
    expect(snapshot.focusInsight.title, contains('아직 학습 기록이 없습니다'));
  });

  test('score-based overview and domain averages are computed correctly', () {
    final snapshot = StatisticsAggregator.build(
      records: [
        _record(
          featureId: LearningFeatureIds.aiFreeTalk,
          domain: LearningDomains.speaking,
          completedAt: now.subtract(const Duration(days: 1)),
          score: 80,
          scoreMax: 100,
          metadata: const <String, dynamic>{
            'dimensionScores': <String, dynamic>{},
          },
        ),
        _record(
          featureId: LearningFeatureIds.toeicWriting,
          domain: LearningDomains.writing,
          completedAt: now.subtract(const Duration(days: 2)),
          score: 70,
          scoreMax: 100,
        ),
      ],
      range: StatisticsRange.all,
      now: now,
    );

    expect(snapshot.overview.averageScorePercent, 75);
    expect(
      snapshot.domainStats
          .firstWhere((item) => item.domain == LearningDomains.speaking)
          .averageScorePercent,
      80,
    );
    expect(
      snapshot.domainStats
          .firstWhere((item) => item.domain == LearningDomains.writing)
          .averageScorePercent,
      70,
    );
  });

  test('vocab quiz accuracy metrics use correctCount and attemptCount', () {
    final snapshot = StatisticsAggregator.build(
      records: [
        _record(
          featureId: LearningFeatureIds.vocabQuiz,
          domain: LearningDomains.vocabulary,
          completedAt: now.subtract(const Duration(hours: 1)),
          attemptCount: 10,
          correctCount: 8,
        ),
        _record(
          featureId: LearningFeatureIds.vocabQuiz,
          domain: LearningDomains.vocabulary,
          completedAt: now.subtract(const Duration(hours: 2)),
          attemptCount: 5,
          correctCount: 5,
        ),
      ],
      range: StatisticsRange.all,
      now: now,
    );

    final vocabQuiz = snapshot.featureStats.firstWhere(
      (item) => item.featureId == LearningFeatureIds.vocabQuiz,
    );

    expect(_metricByLabel(vocabQuiz.metrics, '평균 정답률').value, '87%');
    expect(_metricByLabel(vocabQuiz.metrics, '최고 정답률').value, '100%');
    expect(_metricByLabel(vocabQuiz.metrics, '총 문제 수').value, '15문제');
    expect(_metricByLabel(vocabQuiz.metrics, '맞힌 문제 수').value, '13문제');
  });

  test(
    'range filter updates sessions and excludes scoreless records from average score',
    () {
      final records = [
        _record(
          featureId: LearningFeatureIds.aiTutorChat,
          domain: LearningDomains.speaking,
          completedAt: now.subtract(const Duration(days: 1)),
        ),
        _record(
          featureId: LearningFeatureIds.aiFreeTalk,
          domain: LearningDomains.speaking,
          completedAt: now.subtract(const Duration(days: 1)),
          score: 90,
          scoreMax: 100,
          metadata: const <String, dynamic>{
            'dimensionScores': <String, dynamic>{},
          },
        ),
        _record(
          featureId: LearningFeatureIds.toeicWriting,
          domain: LearningDomains.writing,
          completedAt: now.subtract(const Duration(days: 10)),
          score: 60,
          scoreMax: 100,
        ),
      ];

      final last7 = StatisticsAggregator.build(
        records: records,
        range: StatisticsRange.last7Days,
        now: now,
      );
      final all = StatisticsAggregator.build(
        records: records,
        range: StatisticsRange.all,
        now: now,
      );

      expect(last7.overview.totalSessions, 2);
      expect(last7.overview.averageScorePercent, 90);
      expect(all.overview.totalSessions, 3);
      expect(all.overview.averageScorePercent, 75);
    },
  );

  test(
    'recent activity list is capped at five and focus picks weakest scored domain',
    () {
      final snapshot = StatisticsAggregator.build(
        records: [
          _record(
            featureId: LearningFeatureIds.aiFreeTalk,
            domain: LearningDomains.speaking,
            completedAt: now.subtract(const Duration(hours: 1)),
            score: 92,
            scoreMax: 100,
            metadata: const <String, dynamic>{
              'dimensionScores': <String, dynamic>{},
            },
          ),
          _record(
            featureId: LearningFeatureIds.toeicWriting,
            domain: LearningDomains.writing,
            completedAt: now.subtract(const Duration(hours: 2)),
            score: 61,
            scoreMax: 100,
          ),
          _record(
            featureId: LearningFeatureIds.vocabStudy,
            domain: LearningDomains.vocabulary,
            completedAt: now.subtract(const Duration(hours: 3)),
            attemptCount: 10,
          ),
          _record(
            featureId: LearningFeatureIds.vocabQuiz,
            domain: LearningDomains.vocabulary,
            completedAt: now.subtract(const Duration(hours: 4)),
            attemptCount: 10,
            correctCount: 9,
          ),
          _record(
            featureId: LearningFeatureIds.grammarCheck,
            domain: LearningDomains.writing,
            completedAt: now.subtract(const Duration(hours: 5)),
            metadata: const <String, dynamic>{
              'errorCount': 2,
              'suggestionCount': 2,
            },
          ),
          _record(
            featureId: LearningFeatureIds.toneConversion,
            domain: LearningDomains.writing,
            completedAt: now.subtract(const Duration(hours: 6)),
            metadata: const <String, dynamic>{'tone': 'formal'},
          ),
        ],
        range: StatisticsRange.all,
        now: now,
      );

      expect(snapshot.recentActivities.length, 5);
      expect(snapshot.focusInsight.title, contains('Writing'));
    },
  );
}
