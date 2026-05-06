// FILE: lib/feature/speaking/speaking_page.dart
/*
[역할]
- Speaking 화면 하나로 구성된 MVP 클라이언트.
- 파트 선택(사진/해결/의견) → 녹음 → 업로드 → 서버 응답(Transcript/점수/메트릭) 표시.
- 기본값은 에뮬레이터용 10.0.2.2 이고, 실기기는 dart-define 으로 서버 주소를 주입합니다.
*/

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:dio/dio.dart';
import '../../core/network/server_config.dart';

enum SpeakingPart { photo, solution, opinion }

class SpeakingPage extends StatefulWidget {
  const SpeakingPage({super.key});
  @override
  State<SpeakingPage> createState() => _SpeakingPageState();
}

class _SpeakingPageState extends State<SpeakingPage> {
  // 녹음 컨트롤러
  final _recorder = AudioRecorder();

  // 상태
  bool _isRecording = false;
  bool _isUploading = false;
  DateTime? _recordStart;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  String? _savedPath;

  SpeakingPart _part = SpeakingPart.opinion;

  Map<String, dynamic>? _resp;
  String? _error;

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // 임시 파일 경로 생성 (m4a)
  Future<String> _tempAudioPath() async {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}/turn_$ts.m4a';
  }

  // 녹음 시작
  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        _showSnack('마이크 권한이 필요합니다.', isError: true);
        setState(() => _error = '마이크 권한이 없습니다.');
        return;
      }
      if (_isUploading) return;

      final path = await _tempAudioPath();
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      setState(() {
        _savedPath = path;
        _isRecording = true;
        _recordStart = DateTime.now();
        _elapsed = Duration.zero;
        _error = null;
      });

      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (_recordStart != null) {
          setState(() {
            _elapsed = DateTime.now().difference(_recordStart!);
          });
        }
      });
    } catch (e) {
      _showSnack('녹음 시작 실패: $e', isError: true);
      setState(() => _error = '녹음 시작 실패: $e');
    }
  }

  // 녹음 정지 & 업로드
  Future<void> _stopRecordingAndUpload() async {
    try {
      if (_isUploading) return;

      final path = await _recorder.stop();
      _ticker?.cancel();
      setState(() {
        _isRecording = false;
        _elapsed = DateTime.now().difference(_recordStart ?? DateTime.now());
      });

      final filePath = path ?? _savedPath;
      if (filePath == null) {
        _showSnack('오디오 파일이 없습니다.', isError: true);
        setState(() => _error = '오디오 파일이 없습니다.');
        return;
      }

      final durationMs = _elapsed.inMilliseconds;

      setState(() => _isUploading = true);

      final dio = Dio(BaseOptions(
        baseUrl: serverBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      ));

      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: 'turn.m4a'),
        'duration_ms': durationMs.toString(),
        'part': _part.name,
      });

      final res = await dio.post('/speech/turn', data: form);

      setState(() {
        _resp = Map<String, dynamic>.from(res.data as Map);
        _error = null;
      });
      _showSnack('업로드 완료');
    } catch (e) {
      _showSnack('업로드 실패: $e', isError: true);
      setState(() => _error = '업로드 실패: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // 스낵바
  void _showSnack(String msg, {bool isError = false}) {
    final bar = SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? Colors.red.withValues(alpha: 0.85) : null,
      duration: const Duration(seconds: 2),
    );
    ScaffoldMessenger.of(context).showSnackBar(bar);
  }

  // 00:SS.d 형식(분까지 포함)
  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ds = (d.inMilliseconds.remainder(1000) ~/ 100).toString();
    return '$mm:$ss.$ds';
  }

  // 파트 선택 UI
  Widget _partSelector() {
    return Semantics(
      label: '스피킹 파트 선택',
      child: SegmentedButton<SpeakingPart>(
        segments: const [
          ButtonSegment(value: SpeakingPart.photo, label: Text('사진')),
          ButtonSegment(value: SpeakingPart.solution, label: Text('해결')),
          ButtonSegment(value: SpeakingPart.opinion, label: Text('의견')),
        ],
        selected: {_part},
        onSelectionChanged: (s) => setState(() => _part = s.first),
      ),
    );
  }

  Widget _recordPanel() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  _isRecording ? '녹음 중...' : '대기',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isUploading)
                  Semantics(
                    label: '업로드 중',
                    child: const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('경과: ${_fmt(_elapsed)}'),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_isRecording)
                  Semantics(
                    button: true,
                    label: '녹음 시작',
                    child: FilledButton.icon(
                      onPressed: _isUploading ? null : _startRecording,
                      icon: const Icon(Icons.mic),
                      label: const Text('녹음 시작'),
                    ),
                  ),
                if (_isRecording)
                  Semantics(
                    button: true,
                    label: '정지 후 업로드',
                    child: FilledButton.tonalIcon(
                      onPressed: _isUploading ? null : _stopRecordingAndUpload,
                      icon: const Icon(Icons.stop),
                      label: const Text('정지 & 업로드'),
                    ),
                  ),
              ],
            ),
            if (_savedPath != null) ...[
              const SizedBox(height: 8),
              Text('파일: $_savedPath', style: const TextStyle(fontSize: 12)),
            ],
            if (_error != null && !_isUploading) ...[
              const SizedBox(height: 8),
              Text('오류: $_error', style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  // 점수 게이지
  Widget _scoreGauge(String title, int score) {
    final pct = (score.clamp(0, 100)) / 100.0;
    final level = score >= 85
        ? 'Excellent'
        : score >= 70
            ? 'Good'
            : score >= 50
                ? 'Fair'
                : 'Poor';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('$score / 100 — $level'),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: pct),
          ],
        ),
      ),
    );
  }

  // 메트릭 카드
  Widget _metricsCard(Map<String, dynamic> metrics) {
    final durMs = (metrics['duration_ms'] ?? 0) as int;
    final wc = (metrics['word_count'] ?? 0) as int;
    final wpm = (metrics['wpm'] is num)
        ? (metrics['wpm'] as num).toStringAsFixed(1)
        : metrics['wpm'].toString();

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Row(
              children: [
                Text('녹음 메트릭', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(children: [Expanded(child: Text('길이: ${_fmt(Duration(milliseconds: durMs))}'))]),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: Text('단어 수: $wc')),
                Expanded(child: Text('WPM: $wpm')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 결과 영역
  Widget _resultArea() {
    if (_resp == null) return const SizedBox.shrink();
    final transcript = (_resp?['transcript'] ?? '') as String;
    final scores =
        Map<String, dynamic>.from((_resp?['scores'] as Map?) ?? {});
    final metrics =
        Map<String, dynamic>.from((_resp?['metrics'] as Map?) ?? {});

    return Column(
      children: [
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Row(children: [Text('Transcript', style: TextStyle(fontWeight: FontWeight.bold))]),
                const SizedBox(height: 8),
                SelectableText(transcript),
              ],
            ),
          ),
        ),
        _scoreGauge('발음', (scores['pronunciation'] ?? 0) as int),
        _scoreGauge('유창성', (scores['fluency'] ?? 0) as int),
        _scoreGauge('논리', (scores['logic'] ?? 0) as int),
        _metricsCard(metrics),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Speaking — English AI')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _partSelector(),
          const SizedBox(height: 12),
          _recordPanel(),
          const SizedBox(height: 12),
          if (_resp != null || _error != null) _resultArea(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}



