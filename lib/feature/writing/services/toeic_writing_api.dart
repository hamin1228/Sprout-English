import 'package:dio/dio.dart';

import '../../../core/network/server_config.dart';
import '../models/toeic_writing_models.dart';

class ToeicWritingApi {
  ToeicWritingApi()
    : _dio = Dio(
        BaseOptions(
          baseUrl: serverBaseUrl,
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

  final Dio _dio;

  Future<ToeicWritingPrompt> fetchPrompt({
    required ToeicWritingTaskType taskType,
    required ToeicWritingLevel level,
  }) async {
    final response = await _dio.get(
      '/writing/toeic/prompt',
      queryParameters: <String, dynamic>{
        'task_type': taskType.apiValue,
        'level': level.apiValue,
      },
    );
    return ToeicWritingPrompt.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<ToeicWritingEvaluation> evaluate({
    required ToeicWritingPrompt prompt,
    required int elapsedSec,
    required bool save,
    required String? text,
  }) async {
    final response = await _dio.post(
      '/writing/toeic/eval',
      data: <String, dynamic>{
        'prompt_id': prompt.promptId,
        'task_type': prompt.taskType.apiValue,
        'elapsed_sec': elapsedSec,
        'save': save,
        'submission': <String, dynamic>{'text': text},
      },
    );
    return ToeicWritingEvaluation.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}
