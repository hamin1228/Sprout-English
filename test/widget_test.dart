import 'package:english_ai/core/settings/app_settings_store.dart';
import 'package:english_ai/core/statistics/learning_activity_store.dart';
import 'package:english_ai/feature/roleplay/roleplay_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    AppSettingsStore.instance.debugResetCache();
    await AppSettingsStore.instance.reset();
    LearningActivityStore.instance.debugResetCache();
    await LearningActivityStore.instance.reset();
  });

  testWidgets('roleplay hub opens settings and starts subtitle flow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(home: RoleplayPage()));
    await tester.pumpAndSettle();

    expect(find.text('롤플레잉'), findsOneWidget);
    expect(find.text('롤플레잉 시작'), findsOneWidget);

    await tester.tap(find.text('롤플레잉 시작'));
    await tester.pumpAndSettle();

    expect(find.text('어떤 상황을 연습해볼까요?'), findsOneWidget);
    expect(find.text('자기소개하기'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('자막과 함께 시작'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('대화 자막'), findsOneWidget);
    expect(find.text('Tutor Chloe'), findsOneWidget);
  });

  testWidgets('settings starts non-subtitle flow by default', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(home: RoleplayPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('롤플레잉 시작'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('자막 없이 시작'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('현재 연습 포인트'), findsOneWidget);
    expect(find.text('Tutor Chloe'), findsOneWidget);
  });
}
