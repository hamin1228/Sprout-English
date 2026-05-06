import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/network/server_config.dart';

class LocalSttSwitchPage extends StatefulWidget {
  const LocalSttSwitchPage({super.key});

  @override
  State<LocalSttSwitchPage> createState() => _LocalSttSwitchPageState();
}

class _LocalSttSwitchPageState extends State<LocalSttSwitchPage> {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: serverBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 120),
    ),
  );
  final AudioRecorder _recorder = AudioRecorder();
  final TextEditingController _languageController = TextEditingController(
    text: 'ko',
  );

  bool _loading = false;
  bool _isRecording = false;
  String _statusText = '';
  String _transcript = '';
  String? _recordedPath;
  Map<String, dynamic>? _status;

  @override
  void initState() {
    super.initState();
    _refreshProviderStatus();
  }

  @override
  void dispose() {
    _languageController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _refreshProviderStatus() async {
    setState(() => _loading = true);
    try {
      final response = await _dio.get('/speech/providers');
      final map = Map<String, dynamic>.from(response.data as Map);
      setState(() {
        _status = map;
        _statusText = 'Provider 상태를 갱신했습니다.';
      });
    } catch (e) {
      setState(() {
        _statusText = _friendlyErrorMessage(
          action: 'Provider 상태 조회 실패',
          error: e,
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setActiveProvider() async {
    setState(() => _loading = true);
    try {
      final response = await _dio.post(
        '/speech/provider/active',
        data: <String, dynamic>{
          'provider': 'qwen',
          'language': _languageController.text.trim(),
        },
      );
      final map = Map<String, dynamic>.from(response.data as Map);
      setState(() {
        _status = map;
        _statusText = '활성 provider를 qwen 으로 고정했습니다.';
      });
    } catch (e) {
      setState(() {
        _statusText = _friendlyErrorMessage(
          action: '활성 provider 변경 실패',
          error: e,
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;

    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      setState(() => _statusText = '마이크 권한이 필요합니다.');
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'local_stt_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 128000,
      ),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _recordedPath = path;
      _statusText = '녹음 중...';
    });
  }

  Future<void> _stopAndTranscribe() async {
    if (!_isRecording) return;

    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      _statusText = '전사 요청 중...';
    });

    final audioPath = path ?? _recordedPath;
    if (audioPath == null || !File(audioPath).existsSync()) {
      setState(() => _statusText = '녹음 파일이 없습니다.');
      return;
    }

    setState(() => _loading = true);
    try {
      final query = <String, dynamic>{
        'provider': 'qwen',
        'language': _languageController.text.trim(),
      };

      final form = FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(
          audioPath,
          filename: p.basename(audioPath),
        ),
      });

      final response = await _dio.post(
        '/speech/turn',
        queryParameters: query,
        data: form,
      );
      final map = Map<String, dynamic>.from(response.data as Map);
      final transcript = (map['transcript'] ?? '').toString();
      final provider = (map['provider'] ?? '').toString();
      final model = (map['model'] ?? '').toString();

      setState(() {
        _transcript = transcript;
        _statusText = '전사 완료 provider=$provider model=$model';
      });
    } catch (e) {
      setState(() {
        _statusText = _friendlyErrorMessage(action: '전사 실패', error: e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyErrorMessage({
    required String action,
    required Object error,
  }) {
    final base = '$action: $error';
    if (error is! DioException) return base;

    final errorText = error.toString();
    if (errorText.contains('Connection closed before full header')) {
      return '''
$base

서버 프로세스가 전사 중 종료된 상태일 가능성이 큽니다.
서버를 아래처럼 재시작 후 재시도하세요.

`./scripts/run_local_stt_server.sh`
''';
    }

    if (error.type == DioExceptionType.badResponse) {
      final statusCode = error.response?.statusCode;
      final responseData = error.response?.data;
      return '$base\n\nstatus=$statusCode\nresponse=$responseData';
    }

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.connectionError) {
      return '''
$base

점검 순서:
1) 서버 실행: `./.venv/bin/python -m uvicorn app.main_local_stt:app --host 0.0.0.0 --port 8000`
2) Android 실기기면 USB 연결 후:
   `adb reverse tcp:8000 tcp:8000`
3) 앱 실행 시:
   `--dart-define=ENGLISH_AI_SERVER_BASE_URL=http://127.0.0.1:8000`

현재 앱 baseUrl: $serverBaseUrl
''';
    }

    return base;
  }

  Future<void> _cancelRecording() async {
    if (_isRecording) {
      await _recorder.stop();
    }
    setState(() {
      _isRecording = false;
      _statusText = '녹음을 취소했습니다.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final providers = List<Map<String, dynamic>>.from(
      (_status?['providers'] as List?) ?? const <Map<String, dynamic>>[],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Local STT (Qwen Only)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('서버: $serverBaseUrl'),
                  const SizedBox(height: 8),
                  Text('현재 active: ${_status?['active_provider'] ?? '-'}'),
                  const SizedBox(height: 8),
                  const TextField(
                    enabled: false,
                    decoration: InputDecoration(
                      labelText: 'Provider',
                      hintText: 'qwen',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _languageController,
                    decoration: const InputDecoration(
                      labelText: 'Language (ko/en)',
                      hintText: 'ko',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _loading ? null : _setActiveProvider,
                        child: const Text('활성 Provider 적용'),
                      ),
                      OutlinedButton(
                        onPressed: _loading ? null : _refreshProviderStatus,
                        child: const Text('상태 새로고침'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '빠른 전사 테스트',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: (_loading || _isRecording)
                            ? null
                            : _startRecording,
                        icon: const Icon(Icons.mic),
                        label: const Text('녹음 시작'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: (_loading || !_isRecording)
                            ? null
                            : _stopAndTranscribe,
                        icon: const Icon(Icons.stop),
                        label: const Text('정지 + 전사'),
                      ),
                      OutlinedButton(
                        onPressed: _isRecording ? _cancelRecording : null,
                        child: const Text('취소'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Provider 런타임 상태',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (providers.isEmpty)
                    const Text('-')
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'python=${_status?['python_executable'] ?? '-'}',
                      ),
                    ),
                  if (providers.isNotEmpty)
                    ...providers.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${item['id']} | model=${item['model']} | runtime_ready=${item['runtime_ready']} | preloaded=${item['preloaded']} | active=${item['active']}'
                          '${item['runtime_error'] == null ? '' : ' | runtime_error=${item['runtime_error']}'}',
                        ),
                      ),
                    ),
                  ...providers.map((item) {
                    final warmup = item['warmup'];
                    if (warmup is! Map) {
                      return const SizedBox.shrink();
                    }
                    final ok = warmup['ok'];
                    final elapsedMs = warmup['elapsed_ms'];
                    final error = warmup['error'];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '  warmup: ok=$ok elapsed_ms=$elapsedMs${error == null ? '' : ' error=$error'}',
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Transcript',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(_transcript.isEmpty ? '(없음)' : _transcript),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '상태 메시지',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(_statusText.isEmpty ? '-' : _statusText),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => context.push('/record'),
                child: const Text('Record 화면 열기'),
              ),
              OutlinedButton(
                onPressed: () => context.push('/speaking'),
                child: const Text('Speaking 화면 열기'),
              ),
              OutlinedButton(
                onPressed: () => context.push('/roleplay'),
                child: const Text('Roleplay 화면 열기'),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
