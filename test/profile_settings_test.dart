import 'package:english_ai/core/profile/user_profile_store.dart';
import 'package:english_ai/core/settings/app_settings_store.dart';
import 'package:english_ai/core/statistics/learning_activity_store.dart';
import 'package:english_ai/screens/profile_settings_screen_exact.dart';
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

  testWidgets('profile settings saves display name', (tester) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(
      const MaterialApp(home: ProfileSettingsScreenExact()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('profile_name_field')),
      'Jordan',
    );
    await tester.tap(find.byKey(const ValueKey('profile_save_button')));
    await tester.pumpAndSettle();

    final profile = await UserProfileStore.instance.load();
    expect(profile.displayName, 'Jordan');
  });
}
