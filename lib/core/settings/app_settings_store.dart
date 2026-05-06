import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_settings.dart';

class AppSettingsStore {
  AppSettingsStore._();

  static final AppSettingsStore instance = AppSettingsStore._();
  static const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

  AppSettings? _cached;
  Future<AppSettings>? _pendingLoad;

  Future<AppSettings> load() {
    if (_cached != null) {
      return Future<AppSettings>.value(_cached);
    }
    if (_pendingLoad != null) {
      return _pendingLoad!;
    }
    _pendingLoad = _loadInternal();
    return _pendingLoad!;
  }

  Future<AppSettings> save(AppSettings settings) async {
    _cached = settings;
    final file = await _resolveFile();
    if (file == null) {
      return settings;
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
    return settings;
  }

  Future<AppSettings> update(
    AppSettings Function(AppSettings current) transform,
  ) async {
    final current = await load();
    final next = transform(current);
    return save(next);
  }

  Future<AppSettings> reset() {
    return save(const AppSettings());
  }

  void debugResetCache() {
    _cached = null;
    _pendingLoad = null;
  }

  Future<AppSettings> _loadInternal() async {
    try {
      final file = await _resolveFile();
      if (file == null || !await file.exists()) {
        _cached = const AppSettings();
      } else {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _cached = AppSettings.fromJson(decoded);
      }
    } catch (_) {
      _cached = const AppSettings();
    } finally {
      _pendingLoad = null;
    }
    return _cached!;
  }

  Future<File?> _resolveFile() async {
    if (_isFlutterTest || Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      return File('${directory.path}/app_settings.json');
    } catch (_) {
      return null;
    }
  }
}
