import 'package:english_ai/core/profile/user_profile_store.dart';
import 'package:english_ai/core/settings/app_settings.dart';
import 'package:english_ai/core/settings/app_settings_store.dart';
import 'package:english_ai/core/statistics/learning_activity_store.dart';
import 'package:english_ai/screens/profile_settings_screen_exact.dart';
import 'package:english_ai/screens/push_to_talk_freetalk_screen_exact.dart';
import 'package:english_ai/screens/roleplay_settings_screen_exact.dart';
import 'package:english_ai/screens/settings_page.dart';
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
    UserProfileStore.instance.debugResetCache();
    await UserProfileStore.instance.reset();
    AppSettingsStore.instance.debugResetCache();
    await AppSettingsStore.instance.reset();
    LearningActivityStore.instance.debugResetCache();
    await LearningActivityStore.instance.reset();
  });

  testWidgets('settings page renders sections and excludes study actions', (
    tester,
  ) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('계정'), findsOneWidget);
    expect(find.text('알림'), findsOneWidget);
    expect(find.text('학습 기본값'), findsOneWidget);
    expect(find.text('음성 · 대화'), findsOneWidget);
    expect(find.text('앱'), findsOneWidget);
    expect(find.text('프로필 설정'), findsOneWidget);
    expect(find.text('문의 / 피드백'), findsNothing);
    expect(find.text('AI 프리토킹'), findsNothing);
    expect(find.text('TOEIC Writing'), findsNothing);
  });

  testWidgets('settings page opens profile settings screen', (tester) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('프로필 설정'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileSettingsScreenExact), findsOneWidget);
    expect(find.text('프로필 설정'), findsWidgets);
  });

  testWidgets('settings toggles persist across page re-entry', (tester) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey(AppSettingsStorageKeys.reminderEnabled)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey(AppSettingsStorageKeys.roleplaySubtitleDefault),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Switch>(
            find.byKey(const ValueKey(AppSettingsStorageKeys.reminderEnabled)),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Switch>(
            find.byKey(
              const ValueKey(AppSettingsStorageKeys.roleplaySubtitleDefault),
            ),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('reminder time stays disabled until reminder is enabled', (
    tester,
  ) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    InkWell reminderTile = tester.widget<InkWell>(
      find.byKey(const ValueKey('reminder_time_tile')),
    );
    expect(reminderTile.onTap, isNull);

    await tester.tap(
      find.byKey(const ValueKey(AppSettingsStorageKeys.reminderEnabled)),
    );
    await tester.pumpAndSettle();

    reminderTile = tester.widget<InkWell>(
      find.byKey(const ValueKey('reminder_time_tile')),
    );
    expect(reminderTile.onTap, isNotNull);
  });

  testWidgets('roleplay settings uses subtitle default from app settings', (
    tester,
  ) async {
    _useLargeSurface(tester);

    await AppSettingsStore.instance.save(
      const AppSettings(roleplaySubtitleDefault: true),
    );

    await tester.pumpWidget(
      const MaterialApp(home: RolePlaySettingsScreenExact()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('free talk uses silence auto stop setting as default', (
    tester,
  ) async {
    _useLargeSurface(tester);

    await AppSettingsStore.instance.save(
      const AppSettings(silenceAutoStop: false),
    );

    await tester.pumpWidget(
      const MaterialApp(home: PushToTalkFreeTalkScreenExact()),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('free_talk_auto_stop_off')),
      findsOneWidget,
    );
  });
}
