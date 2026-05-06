import 'package:flutter/material.dart';

import 'core/network/server_config.dart';
import 'core/settings/app_settings_store.dart';
import 'screens/main_tab_shell_page.dart';
import 'screens/theme.dart';
import 'widgets/startup_splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettingsStore.instance.load();
  setServerBaseUrlOverride(settings.serverBaseUrl);
  runApp(const SproutEnglishApp());
}

class SproutEnglishApp extends StatelessWidget {
  const SproutEnglishApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sprout English',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const StartupSplash(child: MainTabShellPage()),
    );
  }
}
