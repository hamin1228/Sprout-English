import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/network/server_config.dart';
import 'core/settings/app_settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettingsStore.instance.load();
  setServerBaseUrlOverride(settings.serverBaseUrl);

  runApp(
    const ProviderScope(
      child: AppBootstrap(
        child: App(),
      ),
    ),
  );
}
