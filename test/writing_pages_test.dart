import 'package:english_ai/core/settings/app_settings_store.dart';
import 'package:english_ai/core/statistics/learning_activity_store.dart';
import 'package:english_ai/feature/writing/toeic_writing_page.dart';
import 'package:english_ai/feature/writing/writing_hub_page.dart';
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

void main() {
  setUp(() async {
    AppSettingsStore.instance.debugResetCache();
    await AppSettingsStore.instance.reset();
    LearningActivityStore.instance.debugResetCache();
    await LearningActivityStore.instance.reset();
  });

  testWidgets('writing hub shows three main tracks', (tester) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: WritingHubPage()));
    await tester.pumpAndSettle();

    expect(find.text('Writing Hub'), findsOneWidget);
    expect(find.text('AI 문법 검사'), findsOneWidget);
    expect(find.text('문장 톤 변환'), findsOneWidget);
    expect(find.textContaining('TOEIC Writing'), findsWidgets);
  });

  testWidgets('toeic writing setup renders practice options', (tester) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: ToeicWritingPage()));
    await tester.pumpAndSettle();

    expect(find.text('실전 유형 선택'), findsOneWidget);
    expect(find.text('사진 묘사'), findsOneWidget);
    expect(find.text('이메일 응답'), findsOneWidget);
    expect(find.text('의견 에세이'), findsOneWidget);
    expect(
      find.textContaining('TOEIC Writing에서 자주 나오는 3가지 유형'),
      findsOneWidget,
    );
  });

  testWidgets('writing hub TOEIC card navigates with Navigator push', (
    tester,
  ) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: WritingHubPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('TOEIC Writing 연습'));
    await tester.pumpAndSettle();
    expect(find.text('실전 유형 선택'), findsOneWidget);
  });

  testWidgets('writing hub grammar card navigates with Navigator push', (
    tester,
  ) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: WritingHubPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AI 문법 검사'));
    await tester.pumpAndSettle();
    expect(find.text('영어 문장을 입력하세요'), findsOneWidget);
  });

  testWidgets('writing hub tone card navigates with Navigator push', (
    tester,
  ) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: WritingHubPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('문장 톤 변환'));
    await tester.pumpAndSettle();
    expect(find.text('Original Sentence'), findsOneWidget);
  });
}
