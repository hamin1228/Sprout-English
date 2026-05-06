import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/theme.dart';
import 'router_local_stt.dart';
import 'widgets/startup_splash.dart';

class AppLocalStt extends ConsumerWidget {
  const AppLocalStt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterLocalSttProvider);

    return MaterialApp.router(
      title: 'AI English Tutor (Local STT Switch)',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
      builder: (context, child) {
        return StartupSplash(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
