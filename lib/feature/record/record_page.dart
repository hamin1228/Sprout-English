import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

import '../../core/audio/recorder_controller.dart';
import '../../core/network/server_config.dart';

class RecordPage extends ConsumerStatefulWidget {
  const RecordPage({super.key});

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<RecordPage> {
  late final AudioPlayer _player;
  String? _lastPlayedPath;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    final s = ref.read(recorderProvider);
    if (s.status == RecStatus.recording) {
      await _handlePressEnd();
    } else {
      await _handlePressStart();
    }
  }

  Future<void> _handlePressStart() async {
    final s = ref.read(recorderProvider);
    if (s.status == RecStatus.uploading) {
      return;
    }
    final ctl = ref.read(recorderProvider.notifier);
    try {
      await ctl.start();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('녹음 오류: $e')));
      }
    }
  }

  Future<void> _handlePressEnd() async {
    final s = ref.read(recorderProvider);
    if (s.status != RecStatus.recording) {
      return;
    }
    final ctl = ref.read(recorderProvider.notifier);
    try {
      // 1) 녹음 종료
      await ctl.stop();
      // 2) 업로드 수행
      final Response res = await ctl.upload();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('/speech/turn 응답: ${res.data}')));
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data.toString() ?? e.message;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('업로드 실패: $msg')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('업로드 실패: $e')));
    }
  }

  Future<void> _play() async {
    final state = ref.read(recorderProvider);
    final path = state.filePath;
    if (path == null) return;

    try {
      if (_lastPlayedPath != path) {
        await _player.setFilePath(path);
        _lastPlayedPath = path;
      }
      await _player.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('재생 오류: $e')));
      }
    }
  }

  Future<void> _upload() async {
    final ctl = ref.read(recorderProvider.notifier);
    try {
      final Response res = await ctl.upload();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('/speech/turn 응답: ${res.data}')));
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data.toString() ?? e.message;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('업로드 실패: $msg')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('업로드 실패: $e')));
    }
  }

  void _cancelUpload() {
    final ctl = ref.read(recorderProvider.notifier);
    ctl.cancelUpload();
  }

  void _goHealthz() {
    context.push('/healthz');
  }

  Future<void> _resetRecorder() async {
    final ctl = ref.read(recorderProvider.notifier);
    await ctl.reset();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recorderProvider);
    final isRec = state.status == RecStatus.recording;
    final isUploading = state.status == RecStatus.uploading;
    final busy = isRec || isUploading;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Tutor · Record POC')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('상태: ${state.status.name}'),
                  const SizedBox(height: 8),
                  if (state.filePath != null)
                    Text(
                      '파일: ${p.basename(state.filePath!)} '
                      '(${state.lastBytes ?? 0} bytes)',
                    ),
                  if (isUploading) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: state.uploadProgress > 0
                          ? state.uploadProgress
                          : null,
                    ),
                  ],
                  if (state.lastMessage != null &&
                      state.lastMessage!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      state.lastMessage!,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Center(
                    child: GestureDetector(
                      onTapDown: (_) => _handlePressStart(),
                      onTapUp: (_) => _handlePressEnd(),
                      onTapCancel: () => _handlePressEnd(),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: busy ? 160 : 140,
                        height: busy ? 160 : 140,
                        decoration: BoxDecoration(
                          color: isRec ? Colors.redAccent : Colors.indigo,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 16,
                              spreadRadius: 2,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          isRec ? Icons.mic : Icons.mic_none,
                          size: 72,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isUploading ? null : _toggleRecord,
                          icon: Icon(isRec ? Icons.stop : Icons.mic),
                          label: Text(isRec ? '정지' : '원터치 녹음'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              (!isRec && state.filePath != null && !isUploading)
                              ? _play
                              : null,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('재생'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              (!isRec && state.filePath != null && !isUploading)
                              ? _upload
                              : null,
                          icon: const Icon(Icons.cloud_upload),
                          label: Text(isUploading ? '업로드 중...' : '서버로 업로드'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isUploading ? _cancelUpload : null,
                          icon: const Icon(Icons.cancel),
                          label: const Text('업로드 취소'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _goHealthz,
                          child: const Text('서버 핑(healthz)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _resetRecorder,
                          child: const Text('리셋'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => context.push('/free_talk'),
                icon: const Icon(Icons.chat),
                label: const Text('Free Talk'),
              ),
              ElevatedButton.icon(
                onPressed: () => context.push('/speaking'),
                icon: const Icon(Icons.mic),
                label: const Text('Speaking'),
              ),
              ElevatedButton.icon(
                onPressed: () => context.push('/writing'),
                icon: const Icon(Icons.edit),
                label: const Text('Writing'),
              ),
              ElevatedButton.icon(
                onPressed: () => context.push('/roleplay'),
                icon: const Icon(Icons.theater_comedy),
                label: const Text('Roleplay'),
              ),
              ElevatedButton.icon(
                onPressed: () => context.push('/drill'),
                icon: const Icon(Icons.school),
                label: const Text('Drill'),
              ),
              ElevatedButton.icon(
                onPressed: () => context.push('/paraphrase'),
                icon: const Icon(Icons.autorenew),
                label: const Text('Paraphrase'),
              ),
              ElevatedButton.icon(
                onPressed: () => context.push('/review'),
                icon: const Icon(Icons.book),
                label: const Text('Review'),
              ),
              ElevatedButton.icon(
                onPressed: () => context.push('/vocab'),
                icon: const Icon(Icons.translate),
                label: const Text('단어 학습'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '현재 서버: $serverBaseUrl',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            '실기기에서는 ENGLISH_AI_SERVER_BASE_URL 을 지정하거나 adb reverse 를 사용하세요.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
