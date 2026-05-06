import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../core/network/server_config.dart';
import 'roleplay_models.dart';

class RoleplayApi {
  RoleplayApi({Dio? dio, AssetBundle? bundle})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: serverBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ),
          ),
      _bundle = bundle ?? rootBundle;

  final Dio _dio;
  final AssetBundle _bundle;

  Future<List<RoleplayCatalogItemModel>> fetchCatalog() async {
    try {
      final response = await _dio.get('/roleplay/catalog');
      final items =
          (response.data['items'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(RoleplayCatalogItemModel.fromJson)
              .toList();
      if (items.isNotEmpty) {
        return items;
      }
    } catch (_) {}

    final fallback = await _bundle.loadString('assets/roleplay/catalog.json');
    final raw = jsonDecode(fallback) as List<dynamic>;
    return raw
        .whereType<Map<String, dynamic>>()
        .map(RoleplayCatalogItemModel.fromJson)
        .toList();
  }

  Future<RoleplayGenerateResult> startSession({
    required String scenarioId,
    required String difficulty,
    String inputSource = 'text',
  }) async {
    final response = await _dio.post(
      '/roleplay/generate',
      data: <String, dynamic>{
        'scenario_id': scenarioId,
        'difficulty': difficulty,
        'input_source': inputSource,
      },
    );
    return RoleplayGenerateResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<RoleplayGenerateResult> continueSession({
    required String sessionId,
    required String scenarioId,
    required String difficulty,
    required String userInput,
    required String inputSource,
  }) async {
    final response = await _dio.post(
      '/roleplay/generate',
      data: <String, dynamic>{
        'session_id': sessionId,
        'scenario_id': scenarioId,
        'difficulty': difficulty,
        'user_input': userInput,
        'input_source': inputSource,
      },
    );
    return RoleplayGenerateResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<RoleplayTranscriptionResult> transcribeAudio(File file) async {
    final form = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.uri.pathSegments.isEmpty
            ? 'roleplay.wav'
            : file.uri.pathSegments.last,
      ),
    });
    final response = await _dio.post('/speech/turn', data: form);
    final map = Map<String, dynamic>.from(response.data as Map);
    final transcript = (map['transcript'] ?? '').toString().trim();
    final error = (map['error'] ?? '').toString().trim();
    return RoleplayTranscriptionResult(
      transcript: transcript.isEmpty ? null : transcript,
      error: error.isEmpty ? null : error,
    );
  }

  Future<Uint8List?> fetchTts({
    required String text,
    required String voice,
    required String model,
    double speed = 1.0,
  }) async {
    try {
      final response = await _dio.post<List<int>>(
        '/tts/speak',
        data: <String, dynamic>{
          'text': text,
          'voice': voice,
          'model': model,
          'speed': speed,
        },
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (error) {
      if (error.response?.statusCode == 503) {
        return null;
      }
      rethrow;
    }
  }
}

class RoleplayTranscriptionResult {
  const RoleplayTranscriptionResult({this.transcript, this.error});

  final String? transcript;
  final String? error;

  bool get hasTranscript => (transcript ?? '').trim().isNotEmpty;
}
