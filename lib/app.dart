import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_controller.dart';
import 'core/theme/theme.dart';
import 'router.dart';
import 'widgets/startup_splash.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'AI English Tutor',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
      builder: (context, child) {
        return StartupSplash(child: child ?? const SizedBox.shrink());
      },
    );
  }
}

// 앱 시작 시 secure storage에서 토큰을 확인해 인증 상태를 초기화한다.
// ProviderScope 아래 최상단 위젯으로 사용한다.
class AppBootstrap extends ConsumerStatefulWidget {
  const AppBootstrap({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<AppBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
