import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'learning_activity_record.dart';

class LearningActivityStore {
  LearningActivityStore._();

  static final LearningActivityStore instance = LearningActivityStore._();
  static const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

  List<LearningActivityRecord>? _cached;
  Future<List<LearningActivityRecord>>? _pendingLoad;

  Future<List<LearningActivityRecord>> load() async {
    if (_cached != null) {
      return List<LearningActivityRecord>.unmodifiable(_cached!);
    }
    if (_pendingLoad != null) {
      return _pendingLoad!;
    }
    _pendingLoad = _loadInternal();
    return _pendingLoad!;
  }

  Future<void> add(LearningActivityRecord record) async {
    final records = List<LearningActivityRecord>.from(await load());
    records.add(record);
    await _saveAll(records);
  }

  Future<void> addAll(Iterable<LearningActivityRecord> records) async {
    final current = List<LearningActivityRecord>.from(await load());
    current.addAll(records);
    await _saveAll(current);
  }

  Future<void> reset() => _saveAll(const <LearningActivityRecord>[]);

  void debugResetCache() {
    _cached = null;
    _pendingLoad = null;
  }

  Future<List<LearningActivityRecord>> _loadInternal() async {
    try {
      final file = await _resolveFile();
      if (file == null || !await file.exists()) {
        _cached = <LearningActivityRecord>[];
      } else {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw) as List<dynamic>;
        _cached = decoded
            .map(
              (item) => LearningActivityRecord.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
      }
    } catch (_) {
      _cached = <LearningActivityRecord>[];
    } finally {
      _pendingLoad = null;
    }

    return List<LearningActivityRecord>.unmodifiable(_cached!);
  }

  Future<void> _saveAll(List<LearningActivityRecord> records) async {
    _cached = List<LearningActivityRecord>.unmodifiable(records);
    final file = await _resolveFile();
    if (file == null) {
      return;
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(records.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<File?> _resolveFile() async {
    if (_isFlutterTest || Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      return File('${directory.path}/learning_activity_records.json');
    } catch (_) {
      return null;
    }
  }
}
