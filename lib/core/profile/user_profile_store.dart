import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'user_profile.dart';

class UserProfileStore {
  UserProfileStore._();

  static final UserProfileStore instance = UserProfileStore._();
  static const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

  UserProfile? _cached;
  Future<UserProfile>? _pendingLoad;

  Future<UserProfile> load() {
    if (_cached != null) {
      return Future<UserProfile>.value(_cached);
    }
    if (_pendingLoad != null) {
      return _pendingLoad!;
    }
    _pendingLoad = _loadInternal();
    return _pendingLoad!;
  }

  Future<UserProfile> save(UserProfile profile) async {
    _cached = profile;
    final file = await _resolveFile();
    if (file == null) {
      return profile;
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(profile.toJson()), flush: true);
    return profile;
  }

  Future<UserProfile> reset() {
    return save(const UserProfile());
  }

  Future<String> importAvatarFile(
    String sourcePath, {
    String? previousPath,
  }) async {
    final targetDirectory = await _resolveAvatarDirectory();
    if (targetDirectory == null) {
      return sourcePath;
    }

    await targetDirectory.create(recursive: true);

    final extension = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final targetPath =
        '${targetDirectory.path}/avatar_${DateTime.now().millisecondsSinceEpoch}$extension';
    final copiedFile = await File(sourcePath).copy(targetPath);

    if (previousPath != null && previousPath != copiedFile.path) {
      final previousFile = File(previousPath);
      if (await previousFile.exists()) {
        await previousFile.delete();
      }
    }

    return copiedFile.path;
  }

  void debugResetCache() {
    _cached = null;
    _pendingLoad = null;
  }

  Future<UserProfile> _loadInternal() async {
    try {
      final file = await _resolveFile();
      if (file == null || !await file.exists()) {
        _cached = const UserProfile();
      } else {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _cached = UserProfile.fromJson(decoded);
      }
    } catch (_) {
      _cached = const UserProfile();
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
      return File('${directory.path}/user_profile.json');
    } catch (_) {
      return null;
    }
  }

  Future<Directory?> _resolveAvatarDirectory() async {
    if (_isFlutterTest || Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      return Directory('${directory.path}/profile');
    } catch (_) {
      return null;
    }
  }
}
