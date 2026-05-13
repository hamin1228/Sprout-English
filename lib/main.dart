import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_controller.dart';
import 'core/network/server_config.dart';
import 'core/settings/app_settings_store.dart';
import 'feature/auth/login_page.dart';
import 'screens/main_tab_shell_page.dart';
import 'screens/theme.dart';
import 'widgets/startup_splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettingsStore.instance.load();
  setServerBaseUrlOverride(settings.serverBaseUrl);
  runApp(const ProviderScope(child: SproutEnglishApp()));
}

class SproutEnglishApp extends ConsumerWidget {
  const SproutEnglishApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Sprout English',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const _AppBootstrap(),
    );
  }
}

// 앱 시작 시 secure storage에서 토큰을 확인해 인증 상태를 초기화하고,
// 인증 여부에 따라 LoginPage 또는 MainTabShellPage를 보여준다.
class _AppBootstrap extends ConsumerStatefulWidget {
  const _AppBootstrap();

  @override
  ConsumerState<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<_AppBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    if (auth.status == AuthStatus.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (auth.status == AuthStatus.authenticated) {
      return const StartupSplash(child: MainTabShellPage());
    }

    return const LoginPage();
  }
}
