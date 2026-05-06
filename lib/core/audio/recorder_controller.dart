import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:english_ai/core/network/client.dart';

enum RecStatus { idle, recording, recorded, uploading }

class RecorderState {
  final RecStatus status;
  final String? filePath;
  final int? lastBytes;
  final double uploadProgress;
  final String? lastMessage;

  const RecorderState({
    required this.status,
    this.filePath,
    this.lastBytes,
    this.uploadProgress = 0,
    this.lastMessage,
  });

  RecorderState copyWith({
    RecStatus? status,
    String? filePath,
    int? lastBytes,
    double? uploadProgress,
    String? lastMessage,
  }) {
    return RecorderState(
      status: status ?? this.status,
      filePath: filePath ?? this.filePath,
      lastBytes: lastBytes ?? this.lastBytes,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }

  factory RecorderState.initial() => const RecorderState(status: RecStatus.idle);
}

final recorderProvider =
    NotifierProvider<RecorderController, RecorderState>(RecorderController.new);

class RecorderController extends Notifier<RecorderState> {
  final AudioRecorder _recorder = AudioRecorder();
  CancelToken? _cancelToken;

  @override
  RecorderState build() {
    // Provider가 dispose될 때 정리
    ref.onDispose(() {
      _recorder.dispose();
      _cancelToken?.cancel('provider disposed');
    });
    return RecorderState.initial();
  }

  Future<void> start() async {
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      throw Exception('마이크 권한이 필요합니다.');
    }

    final dir = await getTemporaryDirectory();
    final path =
        p.join(dir.path, 'rec_${DateTime.now().millisecondsSinceEpoch}.wav');

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 128000,
      ),
      path: path,
    );

    state = state.copyWith(
      status: RecStatus.recording,
      filePath: path,
      lastMessage: '녹음 중…',
      uploadProgress: 0,
    );
  }

  Future<void> stop() async {
    final savedPath = await _recorder.stop();
    final path = savedPath ?? state.filePath;
    if (path == null) {
      state = state.copyWith(
        status: RecStatus.idle,
        filePath: null,
        lastBytes: null,
        uploadProgress: 0,
        lastMessage: null,
      );
      return;
    }
    final bytes = await File(path).length();
    state = state.copyWith(
      status: RecStatus.recorded,
      filePath: path,
      lastBytes: bytes,
      uploadProgress: 0,
      lastMessage: '녹음 완료',
    );
  }

  Future<Response<dynamic>> upload() async {
    final dio = ref.read(dioProvider);
    final path = state.filePath;
    if (path == null || !File(path).existsSync()) {
      throw Exception('업로드할 파일이 없습니다.');
    }

    state = state.copyWith(
      status: RecStatus.uploading,
      uploadProgress: 0,
      lastMessage: '업로드 준비…',
    );

    _cancelToken = CancelToken();

    final backoff = <Duration>[
      const Duration(milliseconds: 500),
      const Duration(seconds: 1),
      const Duration(seconds: 2),
      const Duration(seconds: 4),
    ];

    dynamic lastErr;

    for (var attempt = 0; attempt < backoff.length; attempt++) {
      try {
        final form = FormData.fromMap({
          'file': await MultipartFile.fromFile(
            path,
            filename: p.basename(path),
          ),
        });

        final res = await dio.post(
          '/speech/turn',
          data: form,
          cancelToken: _cancelToken,
          options: Options(
            headers: {
              // 간단한 Idempotency-Key: 파일명 사용
              'X-Idempotency-Key': p.basename(path),
            },
          ),
          onSendProgress: (sent, total) {
            if (total > 0) {
              final progress = sent / total;
              state = state.copyWith(
                uploadProgress: progress,
                lastMessage:
                    '업로드 중… ${(progress * 100).toStringAsFixed(0)}%',
              );
            }
          },
        );

        state = state.copyWith(
          status: RecStatus.recorded,
          uploadProgress: 1.0,
          lastMessage: '완료',
        );
        return res;
      } catch (e) {
        lastErr = e;

        // 사용자가 취소한 경우 즉시 종료
        if (_cancelToken?.isCancelled == true) {
          state = state.copyWith(
            status: RecStatus.recorded,
            uploadProgress: 0,
            lastMessage: '업로드 취소됨',
          );
          throw Exception('업로드가 취소되었습니다.');
        }

        if (attempt == backoff.length - 1) {
          break;
        }

        final delay = backoff[attempt];
        state = state.copyWith(
          lastMessage:
              '재시도 대기 ${delay.inSeconds}s… (시도 ${attempt + 1}/${backoff.length})',
        );
        await Future.delayed(delay);
      }
    }

    state = state.copyWith(
      status: RecStatus.recorded,
      uploadProgress: 0,
      lastMessage: '업로드 실패: $lastErr',
    );
    throw Exception('업로드 실패: $lastErr');
  }

  void cancelUpload() {
    _cancelToken?.cancel('사용자 취소');
  }

  Future<void> reset() async {
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    state = RecorderState.initial();
  }
}
