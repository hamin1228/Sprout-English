import 'package:english_ai/main.dart';
import 'package:english_ai/core/profile/user_profile.dart';
import 'package:english_ai/core/profile/user_profile_store.dart';
import 'package:english_ai/core/settings/app_settings_store.dart';
import 'package:english_ai/core/statistics/learning_activity_record.dart';
import 'package:english_ai/core/statistics/learning_activity_store.dart';
import 'package:english_ai/feature/vocab/vocab_page.dart';
import 'package:english_ai/screens/home_screen_exact.dart';
import 'package:english_ai/screens/main_tab_shell_page.dart';
import 'package:english_ai/screens/settings_page.dart';
import 'package:english_ai/screens/statistics_page.dart';
import 'package:english_ai/screens/study_hub_page.dart';
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
}) {
  return LearningActivityRecord(
    featureId: featureId,
    domain: domain,
    completedAt: completedAt,
    durationSec: durationSec,
  );
}

void main() {
  setUp(() async {
    UserProfileStore.instance.debugResetCache();
    await UserProfileStore.instance.reset();
    AppSettingsStore.instance.debugResetCache();
    await AppSettingsStore.instance.reset();
    LearningActivityStore.instance.debugResetCache();
    await LearningActivityStore.instance.reset();
  });

  testWidgets('app starts on main tab shell home screen', (tester) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(const SproutEnglishApp());
    await tester.pumpAndSettle();

    expect(find.byType(MainTabShellPage), findsOneWidget);
    expect(find.text('Quick Access'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Study'), findsOneWidget);
    expect(find.text('Statistics'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('home greeting changes by local time', (tester) async {
    _useLargeSurface(tester);

    await UserProfileStore.instance.save(
      const UserProfile(displayName: 'Mina'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreenExact(nowProvider: () => DateTime(2026, 1, 1, 9)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Good morning, Mina!'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreenExact(nowProvider: () => DateTime(2026, 1, 1, 14)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Good afternoon, Mina!'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreenExact(nowProvider: () => DateTime(2026, 1, 1, 20)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Good evening, Mina!'), findsOneWidget);
  });

  testWidgets('home TOEIC quick access opens TOEIC writing page', (
    tester,
  ) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: HomeScreenExact()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('TOEIC'));
    await tester.pumpAndSettle();

    expect(find.text('실전 유형 선택'), findsOneWidget);
    expect(find.text('사진 묘사'), findsOneWidget);
  });

  testWidgets('home card swipes to streak summary empty state', (tester) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: HomeScreenExact()));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('home_expression_pageview')),
      const Offset(-1200, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('연속 학습'), findsOneWidget);
    expect(find.text('아직 학습 기록이 없습니다'), findsOneWidget);
    expect(find.text('첫 학습을 시작하면 연속 학습이 쌓입니다.'), findsOneWidget);
  });

  testWidgets('home streak summary shows aggregated metrics', (tester) async {
    _useLargeSurface(tester);

    await LearningActivityStore.instance.add(
      _record(
        featureId: 'ai_free_talk',
        domain: 'speaking',
        completedAt: DateTime.now().subtract(const Duration(days: 1)),
        durationSec: 1500,
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: HomeScreenExact()));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('home_expression_pageview')),
      const Offset(-1200, 0),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home_streak_value')), findsOneWidget);
    expect(find.text('총 세션'), findsOneWidget);
    expect(find.text('총 학습 시간'), findsOneWidget);
    expect(find.text('최근 학습일'), findsOneWidget);
  });

  testWidgets('bottom nav keeps shell while switching root tabs', (
    tester,
  ) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: MainTabShellPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();
    expect(find.byType(StudyHubPage), findsOneWidget);
    expect(find.text('Conversation / Speaking'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);

    await tester.tap(find.text('Statistics'));
    await tester.pumpAndSettle();
    expect(find.byType(StatisticsPage), findsOneWidget);
    expect(find.text('한눈에 보는 학습 요약'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('학습 기본값'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  testWidgets('study tab still opens feature detail with push navigation', (
    tester,
  ) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: MainTabShellPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Study'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('단어 시험').last);
    await tester.pumpAndSettle();

    expect(find.byType(VocabPage), findsOneWidget);
    expect(find.text('단어 시험 설정'), findsOneWidget);
    expect(find.text('시험 시작'), findsOneWidget);
  });
}
