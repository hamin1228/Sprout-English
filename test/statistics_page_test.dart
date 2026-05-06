import 'package:english_ai/core/statistics/learning_activity_record.dart';
import 'package:english_ai/core/statistics/learning_activity_store.dart';
import 'package:english_ai/screens/statistics_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _useLargeSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2200);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
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
  setUp(() async {
    LearningActivityStore.instance.debugResetCache();
    await LearningActivityStore.instance.reset();
  });

  testWidgets(
    'statistics page shows all sections and empty shells without records',
    (tester) async {
      _useLargeSurface(tester);

      await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
      await tester.pumpAndSettle();

      expect(find.text('분야별 통계'), findsOneWidget);
      expect(find.text('기능별 통계'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('이번 주 집중 포인트'), 300);
      expect(find.text('이번 주 집중 포인트'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('최근 활동'), 300);
      expect(find.text('최근 활동'), findsOneWidget);
      expect(find.text('AI 튜터 채팅'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('문장 톤 변환'), 300);
      expect(find.text('문장 톤 변환'), findsOneWidget);
      expect(find.textContaining('아직 기록이 없습니다'), findsWidgets);
    },
  );

  testWidgets('statistics page range filter updates overview session count', (
    tester,
  ) async {
    _useLargeSurface(tester);
    final now = DateTime.now();
    await LearningActivityStore.instance.addAll([
      _record(
        featureId: LearningFeatureIds.aiFreeTalk,
        domain: LearningDomains.speaking,
        completedAt: now.subtract(const Duration(days: 1)),
        score: 82,
        scoreMax: 100,
        metadata: const <String, dynamic>{
          'dimensionScores': <String, dynamic>{},
        },
      ),
      _record(
        featureId: LearningFeatureIds.toeicWriting,
        domain: LearningDomains.writing,
        completedAt: now.subtract(const Duration(days: 10)),
        score: 74,
        scoreMax: 100,
      ),
    ]);

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('overview_sessions_value')))
          .data,
      '1회',
    );

    await tester.tap(find.byKey(const ValueKey('stats_range_all')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('overview_sessions_value')))
          .data,
      '2회',
    );
  });
}
