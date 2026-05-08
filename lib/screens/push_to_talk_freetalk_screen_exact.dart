import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/audio/conversation_audio_session.dart';
import '../core/network/server_config.dart';
import '../core/settings/app_settings_store.dart';
import '../core/statistics/learning_activity_recorder.dart';
import 'speaking_score_card_exact.dart';
import 'speaking_score_models.dart';
import 'theme.dart';

enum _FreeTalkVoiceStage { idle, listening, transcribing, responding, speaking }

class PushToTalkFreeTalkScreenExact extends StatefulWidget {
  const PushToTalkFreeTalkScreenExact({super.key});

  @override
  State<PushToTalkFreeTalkScreenExact> createState() =>
      _PushToTalkFreeTalkScreenExactState();
}

class ChatMessage {
  ChatMessage({
    required this.sender,
    required this.text,
    required this.isUser,
    this.isTyping = false,
    this.translation,
    this.isTranslationExpanded = false,
    this.isTranslating = false,
    this.disableAutoFormatting = false,
  });

  final String sender;
  final String text;
  final bool isUser;
  final bool isTyping;
  final String? translation;
  final bool isTranslationExpanded;
  final bool isTranslating;
  final bool disableAutoFormatting;

  ChatMessage copyWith({
    String? text,
    bool? isTyping,
    String? translation,
    bool clearTranslation = false,
    bool? isTranslationExpanded,
    bool? isTranslating,
    bool? disableAutoFormatting,
  }) {
    return ChatMessage(
      sender: sender,
      text: text ?? this.text,
      isUser: isUser,
      isTyping: isTyping ?? this.isTyping,
      translation: clearTranslation ? null : (translation ?? this.translation),
      isTranslationExpanded:
          isTranslationExpanded ?? this.isTranslationExpanded,
      isTranslating: isTranslating ?? this.isTranslating,
      disableAutoFormatting:
          disableAutoFormatting ?? this.disableAutoFormatting,
    );
  }
}

class _RecordedTurnSnapshot {
  const _RecordedTurnSnapshot({required this.text, required this.durationMs});

  final String text;
  final int durationMs;
}

class _SentenceBatch {
  const _SentenceBatch({required this.sentences, required this.remainder});

  final List<String> sentences;
  final String remainder;
}

class _MemoryAudioSource extends StreamAudioSource {
  _MemoryAudioSource(this.bytes);

  final Uint8List bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final safeStart = start ?? 0;
    final safeEnd = end ?? bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: safeEnd - safeStart,
      offset: safeStart,
      stream: Stream<List<int>>.value(bytes.sublist(safeStart, safeEnd)),
      contentType: 'audio/wav',
    );
  }
}

class _PushToTalkFreeTalkScreenExactState
    extends State<PushToTalkFreeTalkScreenExact> {
  static const int _waveBarCount = 20;
  static const int _waveUiUpdateIntervalMs = 75;
  static const int _localSilenceStopMs = 900;
  static const int _signalSaturationGuardMs = 1200;
  static const int _manualStopIgnoreMs = 1000;
  static const double _localSpeechRmsThreshold = 0.01;
  static const double _localSpeechPeakThreshold = 0.08;
  static const int _softClauseFlushChars = 28;
  static const int _softClauseSearchWindowChars = 72;
  static const bool _softClauseFlushEnabled = false;
  static const bool _ttsSpeakWholeTurn = true;

  final ConversationAudioSession _audioSession = ConversationAudioSession();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  final List<_RecordedTurnSnapshot> _userTurns = [];
  final Map<String, int> _turnPerfMarks = {};
  final ListQueue<Uint8List> _ttsPlaybackQueue = ListQueue<Uint8List>();
  final Map<int, Uint8List?> _readyTtsBySequence = <int, Uint8List?>{};
  final Set<CancelToken> _activeTtsCancelTokens = <CancelToken>{};
  final List<double> _waveformLevels = List<double>.filled(_waveBarCount, 0.18);
  final String _chatUid =
      'ft_${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(1 << 30)}';
  late final Dio _ttsDio = () {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 45),
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.baseUrl = serverBaseUrl;
          handler.next(options);
        },
      ),
    );
    return dio;
  }();

  AudioRecorder? _audioRecorder;
  AudioPlayer _audioPlayer = AudioPlayer();
  WebSocketChannel? _chatChannel;
  StreamSubscription? _chatSubscription;
  WebSocketChannel? _speechChannel;
  StreamSubscription? _speechSubscription;
  StreamSubscription<Uint8List>? _recordStreamSubscription;
  StreamSubscription<PlayerState>? _audioPlayerStateSubscription;

  _FreeTalkVoiceStage _voiceStage = _FreeTalkVoiceStage.idle;

  Timer? _noSpeechTimer;
  DateTime? _sessionStartedAt;
  DateTime? _currentRecordingStartedAt;

  String? _activeTraceId;
  String _liveTranscript = '';
  String _assistantSentenceBuffer = '';

  bool _isSpeechSessionReady = false;
  bool _speechDetected = false;
  bool _localSpeechDetected = false;
  bool _speechStopRequested = false;
  bool _isScoringConversation = false;
  bool _assistantResponseComplete = true;
  bool _hasMarkedFirstSentenceClosed = false;
  bool _autoStopEnabled = true;
  bool _aiVoiceAutoplay = true;
  bool _isInterruptingAssistant = false;

  int _currentRecordingDurationMs = 0;
  int _lastWaveformUpdateMs = 0;
  int _pendingTtsRequests = 0;
  int _ttsSequenceCounter = 0;
  int _nextTtsSequenceToQueue = 0;
  int _ttsGeneration = 0;
  DateTime? _lastLocalSpeechAt;
  DateTime? _saturatedSignalStartedAt;
  DateTime? _lastRateLimitedAt;

  @override
  void initState() {
    super.initState();
    _sessionStartedAt = DateTime.now();
    _messages.add(
      ChatMessage(
        sender: 'AI Tutor',
        text: '마이크 버튼을 누르고 편하게 아무 말이나 해보세요. 제가 자연스럽게 답하면서 대화를 이어갈게요.',
        isUser: false,
        disableAutoFormatting: true,
      ),
    );
    _initChatConnection();
    _bindAudioPlayerState();
    unawaited(_loadConversationSettings());
  }

  Future<void> _loadConversationSettings() async {
    final settings = await AppSettingsStore.instance.load();
    if (!mounted) return;
    setState(() {
      _autoStopEnabled = settings.silenceAutoStop;
      _aiVoiceAutoplay = settings.aiVoiceAutoplay;
    });
  }

  void _bindAudioPlayerState() {
    unawaited(_audioPlayerStateSubscription?.cancel() ?? Future<void>.value());
    _audioPlayerStateSubscription = _audioPlayer.playerStateStream.listen((
      state,
    ) async {
      if (state.playing) {
        if (mounted && _voiceStage != _FreeTalkVoiceStage.listening) {
          setState(() => _voiceStage = _FreeTalkVoiceStage.speaking);
        }
        if (!_turnPerfMarks.containsKey('tts_play_start_ms')) {
          _markPerf('tts_play_start_ms');
        }
      }

      if (state.processingState == ProcessingState.completed) {
        await _playNextQueuedTts();
      }
    });
  }

  @override
  void dispose() {
    _noSpeechTimer?.cancel();
    _recordStreamSubscription?.cancel();
    _chatSubscription?.cancel();
    _speechSubscription?.cancel();
    unawaited(_audioPlayerStateSubscription?.cancel() ?? Future<void>.value());
    _chatChannel?.sink.close();
    _speechChannel?.sink.close();
    unawaited(_disposeAudioRecorder());
    unawaited(_audioPlayer.dispose());
    _ttsDio.close(force: true);
    _scrollController.dispose();
    super.dispose();
  }

  void _initChatConnection() {
    try {
      _chatChannel?.sink.close();
      _chatSubscription?.cancel();

      final baseUri = serverWebSocketUri('/chat/stream');
      final chatUri = baseUri.replace(
        queryParameters: <String, String>{
          ...baseUri.queryParameters,
          'uid': _chatUid,
        },
      );
      _chatChannel = WebSocketChannel.connect(chatUri);
      _chatSubscription = _chatChannel!.stream.listen(
        (message) {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          _handleChatMessage(data);
        },
        onError: (error) => debugPrint('Chat WS Error: $error'),
        onDone: () => debugPrint('Chat WS Closed'),
      );
    } catch (e) {
      debugPrint('Chat Connection failed: $e');
    }
  }

  Future<void> _restartChatConnection() async {
    await _chatSubscription?.cancel();
    _chatSubscription = null;
    try {
      await _chatChannel?.sink.close();
    } catch (_) {
      // ignore chat socket teardown errors
    }
    _chatChannel = null;
    _initChatConnection();
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  Future<void> _toggleRecording() async {
    if (_isInterruptingAssistant) return;
    if (_voiceStage == _FreeTalkVoiceStage.listening) {
      await _stopRealtimeRecording(manualStop: true);
      return;
    }

    if (_voiceStage == _FreeTalkVoiceStage.transcribing) return;
    await _startRealtimeRecording();
  }

  Future<void> _startRealtimeRecording() async {
    try {
      if (_voiceStage == _FreeTalkVoiceStage.listening) return;
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        _showSnack('마이크 권한이 필요합니다.');
        return;
      }

      await _interruptAssistantForRecording();
      await _audioSession.prepareForRecording();
      await _openSpeechSession();
      final recorder = await _createFreshAudioRecorder();

      final stream = await _startRecorderStreamWithRecovery(recorder);

      _clearTurnPerfMarks();
      _markPerf('mic_start_ms');
      _speechDetected = false;
      _localSpeechDetected = false;
      _speechStopRequested = false;
      _liveTranscript = '';
      _currentRecordingStartedAt = DateTime.now();
      _currentRecordingDurationMs = 0;
      _lastLocalSpeechAt = null;
      _saturatedSignalStartedAt = null;
      _lastWaveformUpdateMs = 0;
      _resetWaveform();

      setState(() => _voiceStage = _FreeTalkVoiceStage.listening);

      var sequence = 0;
      _recordStreamSubscription?.cancel();
      _recordStreamSubscription = stream.listen(
        (chunk) async {
          _processLocalAudioChunk(chunk);
          if (!_isSpeechSessionReady || _speechChannel == null) return;
          if (sequence == 0) {
            _markPerf('first_audio_chunk_ms');
          }
          _speechChannel!.sink.add(
            jsonEncode({
              'type': 'audio_chunk',
              'sequence': sequence,
              'audio': base64Encode(chunk),
            }),
          );
          sequence += 1;
          if (_shouldAutoStopFromLocalSilence()) {
            await _stopRealtimeRecording();
          }
        },
        onError: (error) async {
          debugPrint('Record stream error: $error');
          await _cancelSpeechCapture(message: '녹음 스트림 오류가 발생했습니다. 다시 시도해 주세요.');
        },
      );

      _noSpeechTimer?.cancel();
      _noSpeechTimer = Timer(const Duration(seconds: 6), () async {
        if (!_speechDetected &&
            mounted &&
            _voiceStage == _FreeTalkVoiceStage.listening) {
          await _cancelSpeechCapture(message: '말소리가 감지되지 않았습니다. 다시 시도해 주세요.');
        }
      });
    } catch (e) {
      debugPrint('Start recording failed: $e');
      await _cancelSpeechCapture(message: '녹음을 시작할 수 없습니다. 다시 시도해 주세요.');
    }
  }

  Future<void> _openSpeechSession() async {
    await _closeSpeechSession(sendCancel: false);
    _isSpeechSessionReady = false;
    _activeTraceId = null;

    final completer = Completer<void>();
    _speechChannel = WebSocketChannel.connect(
      serverWebSocketUri('/speech/realtime'),
    );

    _speechSubscription = _speechChannel!.stream.listen(
      (message) async {
        final data = jsonDecode(message as String) as Map<String, dynamic>;
        final type = data['type']?.toString() ?? '';
        if (type == 'ready' && !completer.isCompleted) {
          _activeTraceId = data['trace_id']?.toString();
          _isSpeechSessionReady = true;
          completer.complete();
        }
        await _handleSpeechMessage(data);
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(StateError('speech channel closed'));
        }
      },
    );

    _speechChannel!.sink.add(jsonEncode({'type': 'start_session'}));
    await completer.future.timeout(const Duration(seconds: 12));
  }

  Future<void> _handleSpeechMessage(Map<String, dynamic> data) async {
    final type = data['type']?.toString() ?? '';
    switch (type) {
      case 'ready':
        break;
      case 'speech_started':
        _speechDetected = true;
        _localSpeechDetected = true;
        _noSpeechTimer?.cancel();
        _markPerf('speech_started_ms');
        break;
      case 'speech_stopped':
        _markPerf('speech_stopped_ms');
        if (_voiceStage == _FreeTalkVoiceStage.listening &&
            _autoStopEnabled &&
            !_speechStopRequested) {
          await _stopRealtimeRecording();
        }
        break;
      case 'transcript_delta':
        _speechDetected = true;
        _noSpeechTimer?.cancel();
        if (_voiceStage != _FreeTalkVoiceStage.responding &&
            mounted &&
            _voiceStage != _FreeTalkVoiceStage.listening) {
          setState(() => _voiceStage = _FreeTalkVoiceStage.transcribing);
        }
        _markPerf('first_transcript_delta_ms');
        setState(() {
          _liveTranscript += data['text']?.toString() ?? '';
        });
        break;
      case 'transcript_final':
        _speechDetected = true;
        _noSpeechTimer?.cancel();
        _markPerf('final_transcript_ms');
        final text = (data['text'] ?? '').toString().trim();
        await _closeSpeechSession(sendCancel: false);
        if (!mounted) return;
        if (text.isEmpty) {
          setState(() {
            _voiceStage = _FreeTalkVoiceStage.idle;
            _liveTranscript = '';
          });
          _showSnack('말소리가 감지되지 않았습니다. 다시 시도해 주세요.');
          return;
        }
        _liveTranscript = '';
        _handleFinalUserTranscript(text);
        break;
      case 'error':
        final error = data['error']?.toString() ?? 'speech_error';
        await _closeSpeechSession(sendCancel: false);
        if (!mounted) return;
        setState(() {
          _voiceStage = _FreeTalkVoiceStage.idle;
          _liveTranscript = '';
        });
        if (error == 'no_speech_detected') {
          _showSnack('말소리가 감지되지 않았습니다. 다시 시도해 주세요.');
        } else {
          _showSnack('STT 오류가 발생했습니다: $error');
        }
        break;
    }
  }

  Future<void> _stopRealtimeRecording({bool manualStop = false}) async {
    if (_voiceStage != _FreeTalkVoiceStage.listening || _speechStopRequested) {
      return;
    }
    _speechStopRequested = true;
    _noSpeechTimer?.cancel();

    _currentRecordingDurationMs = _currentRecordingStartedAt == null
        ? 0
        : DateTime.now().difference(_currentRecordingStartedAt!).inMilliseconds;

    final shouldIgnoreShortStop =
        _currentRecordingDurationMs < _manualStopIgnoreMs;

    await _recordStreamSubscription?.cancel();
    _recordStreamSubscription = null;
    try {
      await _audioRecorder?.stop();
    } catch (_) {
      // ignore stop errors while tearing down stream recording
    }
    await _disposeAudioRecorder();

    if (shouldIgnoreShortStop) {
      await _closeSpeechSession(sendCancel: true);
      if (!mounted) return;
      setState(() {
        _voiceStage = _FreeTalkVoiceStage.idle;
        _liveTranscript = '';
      });
      return;
    }

    if (_speechChannel != null) {
      _speechChannel!.sink.add(jsonEncode({'type': 'stop_session'}));
    }

    if (mounted) {
      setState(() => _voiceStage = _FreeTalkVoiceStage.transcribing);
    }
  }

  Future<void> _cancelSpeechCapture({required String message}) async {
    _noSpeechTimer?.cancel();
    _speechStopRequested = true;
    await _recordStreamSubscription?.cancel();
    _recordStreamSubscription = null;
    try {
      await _audioRecorder?.stop();
    } catch (_) {
      // ignore
    }
    await _disposeAudioRecorder();
    await _closeSpeechSession(sendCancel: true);
    if (!mounted) return;
    setState(() {
      _voiceStage = _FreeTalkVoiceStage.idle;
      _liveTranscript = '';
    });
    _showSnack(message);
  }

  Future<void> _closeSpeechSession({required bool sendCancel}) async {
    if (sendCancel && _speechChannel != null) {
      try {
        _speechChannel!.sink.add(jsonEncode({'type': 'cancel_session'}));
      } catch (_) {
        // ignore
      }
    }
    await _speechSubscription?.cancel();
    _speechSubscription = null;
    try {
      await _speechChannel?.sink.close();
    } catch (_) {
      // ignore
    }
    _speechChannel = null;
    _isSpeechSessionReady = false;
    _speechDetected = false;
    _localSpeechDetected = false;
    _speechStopRequested = false;
    _currentRecordingStartedAt = null;
    _lastLocalSpeechAt = null;
    _saturatedSignalStartedAt = null;
    _resetWaveform();
  }

  void _handleFinalUserTranscript(String text) {
    setState(() {
      _messages.add(ChatMessage(sender: 'You', text: text, isUser: true));
      _userTurns.add(
        _RecordedTurnSnapshot(
          text: text,
          durationMs: _currentRecordingDurationMs,
        ),
      );
      _messages.add(
        ChatMessage(
          sender: 'AI Tutor',
          text: '',
          isUser: false,
          isTyping: true,
        ),
      );
      _voiceStage = _FreeTalkVoiceStage.responding;
    });
    _scrollToBottom();
    _assistantResponseComplete = false;
    _assistantSentenceBuffer = '';
    _sendPromptToChat(text);
  }

  void _sendPromptToChat(String prompt) {
    if (_chatChannel == null) {
      _initChatConnection();
    }
    final channel = _chatChannel;
    if (channel == null) {
      _showSnack('채팅 연결을 초기화할 수 없습니다.');
      return;
    }

    channel.sink.add(
      jsonEncode({
        'type': 'start',
        'prompt': prompt,
        'trace_id': _activeTraceId,
        'history': _buildChatHistory(),
      }),
    );
  }

  List<Map<String, String>> _buildChatHistory() {
    return _messages
        .skip(1)
        .where((message) => !message.isTyping && message.text.trim().isNotEmpty)
        .map(
          (message) => {
            'role': message.isUser ? 'user' : 'assistant',
            'content': message.text.trim(),
          },
        )
        .toList();
  }

  Future<void> _handleChatMessage(Map<String, dynamic> data) async {
    final type = data['type']?.toString() ?? '';
    switch (type) {
      case 'init':
        break;
      case 'delta':
        final chunk = data['text']?.toString() ?? '';
        if (_messages.isNotEmpty && !_messages.last.isUser) {
          final currentText = _messages.last.isTyping
              ? ''
              : _messages.last.text;
          if (!_turnPerfMarks.containsKey('llm_first_token_ms')) {
            _markPerf('llm_first_token_ms');
          }
          setState(() {
            _messages.last = _messages.last.copyWith(
              text: currentText + chunk,
              isTyping: false,
            );
            if (_voiceStage != _FreeTalkVoiceStage.listening &&
                _voiceStage != _FreeTalkVoiceStage.transcribing &&
                _voiceStage != _FreeTalkVoiceStage.speaking) {
              _voiceStage = _FreeTalkVoiceStage.responding;
            }
          });
          _consumeAssistantTextForTts(chunk);
          _scrollToBottom();
        }
        break;
      case 'done':
        final translation = (data['translation'] ?? '').toString().trim();
        if (_messages.isNotEmpty && !_messages.last.isUser) {
          setState(() {
            _messages.last = _messages.last.copyWith(
              translation: translation.isEmpty ? null : translation,
            );
          });
        }
        _assistantResponseComplete = true;
        await _flushAssistantTtsRemainder();
        _settleVoiceStageAfterAssistant();
        break;
      case 'translation':
        final translation = (data['translation'] ?? '').toString().trim();
        if (translation.isNotEmpty &&
            _messages.isNotEmpty &&
            !_messages.last.isUser) {
          setState(() {
            _messages.last = _messages.last.copyWith(translation: translation);
          });
        }
        break;
      case 'error':
        final errorCode = data['error']?.toString() ?? 'unknown';
        if (errorCode == 'rate_limited') {
          final now = DateTime.now();
          if (_lastRateLimitedAt != null &&
              now.difference(_lastRateLimitedAt!).inMilliseconds < 1500) {
            return;
          }
          _lastRateLimitedAt = now;
        }
        if (!mounted) return;
        setState(() {
          _messages.add(
            ChatMessage(
              sender: 'System',
              text: 'Error: $errorCode',
              isUser: false,
            ),
          );
          _voiceStage = _FreeTalkVoiceStage.idle;
        });
        _scrollToBottom();
        break;
    }
  }

  void _consumeAssistantTextForTts(String chunk) {
    if (!_aiVoiceAutoplay) return;
    _assistantSentenceBuffer += chunk;
    if (_ttsSpeakWholeTurn) return;
    final batch = _extractCompleteSentences(_assistantSentenceBuffer);
    _assistantSentenceBuffer = batch.remainder;

    for (final sentence in batch.sentences) {
      _enqueueTtsSentence(sentence);
    }
  }

  Future<void> _flushAssistantTtsRemainder() async {
    if (!_aiVoiceAutoplay) {
      _assistantSentenceBuffer = '';
      return;
    }
    final trailing = _assistantSentenceBuffer.trim();
    _assistantSentenceBuffer = '';
    if (trailing.isNotEmpty) {
      _enqueueTtsSentence(trailing);
    }
  }

  _SentenceBatch _extractCompleteSentences(String buffer) {
    final sentences = <String>[];
    var working = buffer;

    final hardMatches = RegExp(
      r'(.+?[.!?。！？]+(?:\s+|$))',
      dotAll: true,
    ).allMatches(working).toList();
    var lastEnd = 0;
    for (final match in hardMatches) {
      final sentence = match.group(0)?.trim() ?? '';
      if (sentence.isNotEmpty) {
        sentences.add(sentence);
      }
      lastEnd = match.end;
    }
    if (lastEnd > 0) {
      working = working.substring(lastEnd);
    }

    // Fast-start fallback: if punctuation hasn't appeared yet, flush a clause
    // once the buffered text is long enough so TTS can start earlier.
    if (_softClauseFlushEnabled) {
      while (working.trim().length >= _softClauseFlushChars) {
        final boundary = _findSoftClauseBoundary(working);
        if (boundary <= 0 || boundary > working.length) {
          break;
        }
        final clause = working.substring(0, boundary).trim();
        if (clause.isNotEmpty) {
          sentences.add(clause);
        }
        working = working.substring(boundary).trimLeft();
      }
    }

    return _SentenceBatch(sentences: sentences, remainder: working);
  }

  int _findSoftClauseBoundary(String text) {
    final limit = math.min(text.length, _softClauseSearchWindowChars);
    if (limit <= _softClauseFlushChars) {
      return -1;
    }
    const punctuation = <String>{',', '，', ';', ':', '—', '-'};
    for (var i = limit - 1; i >= _softClauseFlushChars; i -= 1) {
      final ch = text[i];
      if (punctuation.contains(ch)) {
        return i + 1;
      }
    }
    for (var i = limit - 1; i >= _softClauseFlushChars; i -= 1) {
      if (text[i] == ' ') {
        return i + 1;
      }
    }
    return -1;
  }

  bool _isRetryableTtsError(DioException error) {
    final statusCode = error.response?.statusCode ?? 0;
    if (statusCode == 429 ||
        statusCode == 500 ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504) {
      return true;
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return true;
      case DioExceptionType.badResponse:
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
        return false;
    }
  }

  Future<Uint8List> _requestTtsBytesWithRetry({
    required String text,
    required CancelToken cancelToken,
  }) async {
    const maxAttempts = 2;
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      if (cancelToken.isCancelled) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: '/tts/speak'),
          reason: 'assistant interrupted',
        );
      }

      try {
        final response = await _ttsDio.post<List<int>>(
          '/tts/speak',
          data: {
            'text': text,
            'voice': 'nova',
            'model': 'gpt-4o-mini-tts',
            'speed': 1.0,
          },
          options: Options(responseType: ResponseType.bytes),
          cancelToken: cancelToken,
        );
        return Uint8List.fromList(response.data ?? const <int>[]);
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) rethrow;
        final shouldRetry =
            attempt < maxAttempts && _isRetryableTtsError(error);
        if (!shouldRetry) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
    }

    throw StateError('unreachable');
  }

  Future<void> _enqueueTtsSentence(String sentence) async {
    final trimmed = sentence.trim();
    if (trimmed.isEmpty) return;

    final sequence = _ttsSequenceCounter++;
    final generation = _ttsGeneration;
    if (!_hasMarkedFirstSentenceClosed) {
      _hasMarkedFirstSentenceClosed = true;
      _markPerf('first_sentence_closed_ms');
    }

    _pendingTtsRequests += 1;
    if (!_turnPerfMarks.containsKey('tts_request_ms')) {
      _markPerf('tts_request_ms');
    }

    final cancelToken = CancelToken();
    _activeTtsCancelTokens.add(cancelToken);
    try {
      final bytes = await _requestTtsBytesWithRetry(
        text: trimmed,
        cancelToken: cancelToken,
      );
      if (generation != _ttsGeneration) return;
      if (bytes.isEmpty) {
        _readyTtsBySequence[sequence] = null;
      } else {
        if (!_turnPerfMarks.containsKey('tts_response_ms')) {
          _markPerf('tts_response_ms');
        }
        _readyTtsBySequence[sequence] = bytes;
      }
    } catch (e) {
      debugPrint('TTS sentence failed: $e');
      if (generation == _ttsGeneration) {
        _readyTtsBySequence[sequence] = null;
      }
      final wasCanceled = e is DioException && CancelToken.isCancel(e);
      if (mounted && !wasCanceled) {
        _showSnack('일부 음성 재생을 건너뛰었습니다.');
      }
    } finally {
      _activeTtsCancelTokens.remove(cancelToken);
      if (generation == _ttsGeneration) {
        _pendingTtsRequests -= 1;
        await _drainReadyTtsQueue();
      }
    }
  }

  Future<void> _drainReadyTtsQueue() async {
    while (_readyTtsBySequence.containsKey(_nextTtsSequenceToQueue)) {
      final bytes = _readyTtsBySequence.remove(_nextTtsSequenceToQueue);
      if (bytes != null) {
        _ttsPlaybackQueue.add(bytes);
      }
      _nextTtsSequenceToQueue += 1;
    }

    if (!_audioPlayer.playing && _ttsPlaybackQueue.isNotEmpty) {
      await _playNextQueuedTts();
      return;
    }

    _settleVoiceStageAfterAssistant();
  }

  Future<void> _playNextQueuedTts() async {
    if (_ttsPlaybackQueue.isEmpty) {
      _settleVoiceStageAfterAssistant();
      return;
    }

    final nextBytes = _ttsPlaybackQueue.removeFirst();
    try {
      await _audioSession.prepareForPlayback();
      await _audioPlayer.setAudioSource(_MemoryAudioSource(nextBytes));
      await _audioPlayer.play();
      if (mounted && _voiceStage != _FreeTalkVoiceStage.listening) {
        setState(() => _voiceStage = _FreeTalkVoiceStage.speaking);
      }
    } catch (e) {
      debugPrint('TTS playback failed: $e');
      await _playNextQueuedTts();
    }
  }

  void _settleVoiceStageAfterAssistant() {
    if (!mounted) return;
    final hasPendingSpeech =
        _pendingTtsRequests > 0 ||
        _ttsPlaybackQueue.isNotEmpty ||
        _audioPlayer.playing;
    if (hasPendingSpeech) {
      if (_voiceStage != _FreeTalkVoiceStage.listening &&
          _voiceStage != _FreeTalkVoiceStage.transcribing) {
        setState(() => _voiceStage = _FreeTalkVoiceStage.speaking);
      }
      return;
    }

    if (_assistantResponseComplete &&
        _voiceStage != _FreeTalkVoiceStage.listening &&
        _voiceStage != _FreeTalkVoiceStage.transcribing) {
      setState(() => _voiceStage = _FreeTalkVoiceStage.idle);
    }
  }

  Future<void> _interruptAssistantForRecording() async {
    if (_isInterruptingAssistant) return;
    setState(() => _isInterruptingAssistant = true);
    try {
      await _resetAssistantSpeechPipeline(
        deactivateAudioSession: true,
        reconnectChat: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 140));
    } finally {
      if (mounted) {
        setState(() => _isInterruptingAssistant = false);
      } else {
        _isInterruptingAssistant = false;
      }
    }
  }

  Future<void> _resetAssistantSpeechPipeline({
    bool deactivateAudioSession = false,
    bool reconnectChat = false,
  }) async {
    _ttsGeneration += 1;
    _assistantResponseComplete = true;
    _assistantSentenceBuffer = '';
    _hasMarkedFirstSentenceClosed = false;
    _pendingTtsRequests = 0;
    _ttsSequenceCounter = 0;
    _nextTtsSequenceToQueue = 0;

    for (final token in _activeTtsCancelTokens.toList()) {
      token.cancel('assistant interrupted');
    }
    _activeTtsCancelTokens.clear();

    await _audioPlayer.stop();
    _ttsPlaybackQueue.clear();
    _readyTtsBySequence.clear();
    await _resetAudioPlaybackEngine();
    if (deactivateAudioSession) {
      await _audioSession.deactivate();
    }
    if (reconnectChat) {
      await _restartChatConnection();
    }
  }

  String _formatAiMessageForDisplay(String text) {
    final compact = text.trim();
    if (compact.isEmpty) return compact;
    final withParagraphs = compact.replaceAllMapped(
      RegExp(r'([.!?])\s+'),
      (match) => '${match.group(1)}\n\n',
    );
    return withParagraphs.replaceAllMapped(
      RegExp(r'([:;])\s+'),
      (match) => '${match.group(1)}\n',
    );
  }

  Future<void> _toggleAiTranslation(int index) async {
    if (index < 0 || index >= _messages.length) return;
    final message = _messages[index];
    if (message.isUser || message.isTyping || message.text.trim().isEmpty) {
      return;
    }
    if ((message.translation ?? '').trim().isEmpty) return;
    setState(() {
      _messages[index] = message.copyWith(
        isTranslationExpanded: !message.isTranslationExpanded,
      );
    });
  }

  Future<void> _finishConversation() async {
    if (_isScoringConversation ||
        _voiceStage == _FreeTalkVoiceStage.listening ||
        _isInterruptingAssistant) {
      return;
    }
    if (_userTurns.isEmpty) {
      _showSnack('채점할 대화가 없습니다. 먼저 프리토킹을 진행해 주세요.');
      return;
    }

    setState(() => _isScoringConversation = true);
    try {
      await _resetAssistantSpeechPipeline(
        deactivateAudioSession: true,
        reconnectChat: true,
      );
      final dio = Dio();
      final response = await dio.post(
        '$serverBaseUrl/speaking/free-talk/score',
        data: _buildScoringPayload(),
      );

      if (!mounted) return;
      final result = SpeakingScoreResult.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      await LearningActivityRecorder.recordFreeTalk(
        durationSec: DateTime.now()
            .difference(_sessionStartedAt ?? DateTime.now())
            .inSeconds,
        userTurnCount: _userTurns.length,
        result: result,
      );
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SpeakingScoreCardExact(
            result: result,
            completedAt: DateTime.now(),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        _showSnack('채점 요청에 실패했습니다: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isScoringConversation = false);
      }
    }
  }

  Map<String, dynamic> _buildScoringPayload() {
    final conversationTurns = _messages
        .skip(1)
        .where((message) => message.text.trim().isNotEmpty)
        .map(
          (message) => {
            'speaker': message.isUser ? 'user' : 'partner',
            'text': message.text.trim(),
          },
        )
        .toList();

    final userTranscript = _userTurns
        .map((turn) => turn.text.trim())
        .where((text) => text.isNotEmpty)
        .join(' ');

    final totalUserDurationMs = _userTurns.fold<int>(
      0,
      (sum, turn) => sum + turn.durationMs,
    );
    final totalWordCount = RegExp(
      r"[A-Za-z']+",
    ).allMatches(userTranscript).length;
    final speechRateWpm = totalUserDurationMs > 0
        ? (totalWordCount / (totalUserDurationMs / 60000))
        : 0.0;

    return {
      'task': {
        'task_id': 'free_talk_${DateTime.now().millisecondsSinceEpoch}',
        'task_type': 'free_talk',
        'prompt': 'Open free conversation with an AI English tutor.',
        'expected_functions': [
          'answer naturally',
          'maintain the conversation',
          'develop ideas with supporting details',
          'respond to follow-up questions',
        ],
        'context': {
          'role': 'learner',
          'situation': 'free talking practice',
          'difficulty': 'A2-B1',
        },
      },
      'response': {'transcript': userTranscript, 'turns': conversationTurns},
      'speech_features': {
        'speech_rate_wpm': speechRateWpm,
        'pause_count': null,
        'long_pause_count': null,
        'avg_pause_ms': null,
        'pronunciation_intelligibility_estimate': null,
        'total_user_duration_ms': totalUserDurationMs,
        'user_turn_count': _userTurns.length,
        'session_duration_ms': DateTime.now()
            .difference(_sessionStartedAt ?? DateTime.now())
            .inMilliseconds,
      },
      'language': {'native_language': 'ko', 'target_language': 'en'},
    };
  }

  void _clearTurnPerfMarks() {
    _turnPerfMarks.clear();
  }

  void _processLocalAudioChunk(Uint8List chunk) {
    if (chunk.length < 2) return;

    final byteData = ByteData.sublistView(chunk);
    var peak = 0.0;
    var sumSquares = 0.0;
    var sampleCount = 0;

    for (var i = 0; i + 1 < chunk.length; i += 2) {
      final sample = byteData.getInt16(i, Endian.little) / 32768.0;
      final absSample = sample.abs();
      if (absSample > peak) {
        peak = absSample;
      }
      sumSquares += sample * sample;
      sampleCount += 1;
    }

    if (sampleCount == 0) return;

    final rms = (sumSquares / sampleCount) <= 0
        ? 0.0
        : math.sqrt(sumSquares / sampleCount);
    final now = DateTime.now();
    final speaking =
        rms >= _localSpeechRmsThreshold || peak >= _localSpeechPeakThreshold;

    if (speaking) {
      _speechDetected = true;
      _localSpeechDetected = true;
      _lastLocalSpeechAt = now;
      _noSpeechTimer?.cancel();
    }

    final normalizedLevel = _normalizeWaveLevel(rms: rms, peak: peak);
    if (_isSaturatedSignal(normalizedLevel, rms)) {
      _saturatedSignalStartedAt ??= now;
      if (_voiceStage == _FreeTalkVoiceStage.listening &&
          !_speechStopRequested &&
          now.difference(_saturatedSignalStartedAt!).inMilliseconds >=
              _signalSaturationGuardMs) {
        unawaited(_cancelSpeechCapture(message: '마이크 입력이 불안정합니다. 다시 시도해 주세요.'));
        return;
      }
    } else {
      _saturatedSignalStartedAt = null;
    }

    final nowMs = now.millisecondsSinceEpoch;
    if (nowMs - _lastWaveformUpdateMs >= _waveUiUpdateIntervalMs) {
      _lastWaveformUpdateMs = nowMs;
      _updateWaveform(normalizedLevel);
    }
  }

  bool _shouldAutoStopFromLocalSilence() {
    if (_voiceStage != _FreeTalkVoiceStage.listening ||
        !_autoStopEnabled ||
        _speechStopRequested ||
        !_localSpeechDetected ||
        _lastLocalSpeechAt == null) {
      return false;
    }

    return DateTime.now().difference(_lastLocalSpeechAt!).inMilliseconds >=
        _localSilenceStopMs;
  }

  double _normalizeWaveLevel({required double rms, required double peak}) {
    final level = (rms * 7.5) > (peak * 1.6) ? (rms * 7.5) : (peak * 1.6);
    return level.clamp(0.0, 1.0);
  }

  bool _isSaturatedSignal(double normalizedLevel, double rms) {
    return normalizedLevel >= 0.97 && rms >= 0.35;
  }

  void _updateWaveform(double level) {
    if (!mounted) return;
    setState(() {
      for (var index = 0; index < _waveBarCount; index += 1) {
        final centerDistance = (index - (_waveBarCount - 1) / 2).abs();
        final envelope = 1.0 - (centerDistance / (_waveBarCount / 2));
        final shaped = 0.14 + (level * (0.28 + envelope * 0.58));
        _waveformLevels[index] = shaped.clamp(0.14, 1.0);
      }
    });
  }

  void _resetWaveform() {
    if (!mounted) return;
    setState(() {
      for (var index = 0; index < _waveBarCount; index += 1) {
        _waveformLevels[index] = 0.18;
      }
    });
  }

  void _markPerf(String key) {
    if (_turnPerfMarks.containsKey(key)) return;
    final value = DateTime.now().millisecondsSinceEpoch;
    _turnPerfMarks[key] = value;
    debugPrint('[FreeTalk][$key][trace=${_activeTraceId ?? "-"}] $value');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resetAudioPlaybackEngine() async {
    final previousPlayer = _audioPlayer;
    final previousSubscription = _audioPlayerStateSubscription;
    _audioPlayerStateSubscription = null;
    await previousSubscription?.cancel();
    _audioPlayer = AudioPlayer();
    _bindAudioPlayerState();
    try {
      await previousPlayer.dispose();
    } catch (_) {
      // ignore playback teardown errors
    }
  }

  Future<AudioRecorder> _createFreshAudioRecorder() async {
    await _disposeAudioRecorder();
    final recorder = AudioRecorder();
    _audioRecorder = recorder;
    return recorder;
  }

  Future<void> _disposeAudioRecorder() async {
    final recorder = _audioRecorder;
    _audioRecorder = null;
    if (recorder == null) return;
    try {
      if (await recorder.isRecording()) {
        await recorder.stop();
      }
    } catch (_) {
      // ignore recorder teardown errors
    }
    try {
      await recorder.dispose();
    } catch (_) {
      // ignore recorder teardown errors
    }
  }

  Future<Stream<Uint8List>> _startRecorderStreamWithRecovery(
    AudioRecorder recorder,
  ) async {
    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 24000,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
      streamBufferSize: 4800,
    );
    try {
      return await recorder.startStream(config);
    } catch (_) {
      await _disposeAudioRecorder();
      final freshRecorder = await _createFreshAudioRecorder();
      await _audioSession.prepareForRecording();
      return freshRecorder.startStream(config);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _statusText() {
    switch (_voiceStage) {
      case _FreeTalkVoiceStage.idle:
        return 'Tap to Speak';
      case _FreeTalkVoiceStage.listening:
        return _autoStopEnabled
            ? 'Listening... Auto stop is on'
            : 'Listening... Tap again to stop';
      case _FreeTalkVoiceStage.transcribing:
        return _liveTranscript.isEmpty
            ? 'Transcribing...'
            : 'Transcribing... $_liveTranscript';
      case _FreeTalkVoiceStage.responding:
        return 'AI is responding...';
      case _FreeTalkVoiceStage.speaking:
        return 'Playing AI voice...';
    }
  }

  Color _statusColor() {
    switch (_voiceStage) {
      case _FreeTalkVoiceStage.listening:
        return Colors.red;
      case _FreeTalkVoiceStage.responding:
      case _FreeTalkVoiceStage.speaking:
        return AppTheme.primary;
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'AI 프리토킹',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isScoringConversation ? null : _finishConversation,
            icon: _isScoringConversation
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.assessment, color: AppTheme.primary),
            label: Text(
              _isScoringConversation ? '채점 중' : '대화 종료',
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: message.isUser
                      ? _buildUserMessage(message.text)
                      : _buildAiMessage(message, index),
                );
              },
            ),
          ),
          _buildMicArea(),
        ],
      ),
    );
  }

  Widget _buildAiMessage(ChatMessage message, int index) {
    final displayText = message.disableAutoFormatting
        ? message.text.trim()
        : _formatAiMessageForDisplay(message.text);
    final translationText = message.disableAutoFormatting
        ? (message.translation ?? '').trim()
        : _formatAiMessageForDisplay(message.translation ?? '');
    final canShowTranslation =
        !message.isTyping && translationText.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI Tutor',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  border: Border.all(color: AppTheme.borderLight),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayText.isEmpty ? '...' : displayText,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: AppTheme.textDark,
                      ),
                    ),
                    if (canShowTranslation) ...[
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () => _toggleAiTranslation(index),
                        borderRadius: BorderRadius.circular(10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              message.isTranslationExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 18,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              '해석 보기',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (message.isTranslationExpanded &&
                        canShowTranslation) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          translationText,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.55,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserMessage(String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'You',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[300],
          ),
        ),
      ],
    );
  }

  Widget _buildMicArea() {
    final isListening = _voiceStage == _FreeTalkVoiceStage.listening;
    final isBusy =
        _voiceStage == _FreeTalkVoiceStage.transcribing ||
        _isScoringConversation;
    const autoStopWidth = 148.0;
    const micSize = 84.0;
    const gap = 18.0;
    const toggleWidth = 92.0;
    const toggleHeight = 38.0;
    const controlHeight = 112.0;
    const labelBottomGap = 14.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        border: Border(top: BorderSide(color: AppTheme.borderLight)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              height: 64,
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_waveBarCount, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 3,
                    height: 12 + (_waveformLevels[index] * 42),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isListening
                          ? Colors.redAccent
                          : AppTheme.primary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: controlHeight,
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final centerX = constraints.maxWidth / 2;
                  final micLeft = centerX - (micSize / 2);
                  final desiredControlLeft = micLeft - gap - autoStopWidth;
                  final controlLeft = desiredControlLeft < 0
                      ? 0.0
                      : desiredControlLeft;
                  final switchTop = (controlHeight - toggleHeight) / 2;

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: micLeft,
                        top: (controlHeight - micSize) / 2,
                        child: GestureDetector(
                          onTap: isBusy ? null : _toggleRecording,
                          child: Container(
                            width: micSize,
                            height: micSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isListening
                                  ? Colors.red
                                  : AppTheme.primary,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (isListening
                                              ? Colors.red
                                              : AppTheme.primary)
                                          .withValues(alpha: 0.3),
                                  blurRadius: 22,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Icon(
                              isBusy ? Icons.hourglass_empty : Icons.mic,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: controlLeft,
                        top: 0,
                        width: autoStopWidth,
                        height: controlHeight,
                        child: KeyedSubtree(
                          key: ValueKey(
                            'free_talk_auto_stop_${_autoStopEnabled ? 'on' : 'off'}',
                          ),
                          child: Opacity(
                            opacity: isBusy ? 0.6 : 1,
                            child: IgnorePointer(
                              ignoring: isBusy,
                              child: Stack(
                                children: [
                                  Positioned(
                                    top: switchTop,
                                    left: (autoStopWidth - toggleWidth) / 2,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        onTap: () {
                                          setState(
                                            () => _autoStopEnabled =
                                                !_autoStopEnabled,
                                          );
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          width: toggleWidth,
                                          height: toggleHeight,
                                          padding: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            color: Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: _autoStopEnabled
                                                  ? AppTheme.primary
                                                  : AppTheme.textSecondary
                                                        .withValues(
                                                          alpha: 0.35,
                                                        ),
                                              width: 1.4,
                                            ),
                                          ),
                                          child: Stack(
                                            children: [
                                              AnimatedAlign(
                                                duration: const Duration(
                                                  milliseconds: 180,
                                                ),
                                                curve: Curves.easeOut,
                                                alignment: _autoStopEnabled
                                                    ? Alignment.centerRight
                                                    : Alignment.centerLeft,
                                                child: Container(
                                                  width: (toggleWidth - 6) / 2,
                                                  height: toggleHeight - 6,
                                                  decoration: BoxDecoration(
                                                    color: _autoStopEnabled
                                                        ? AppTheme.primary
                                                        : AppTheme.textSecondary
                                                              .withValues(
                                                                alpha: 0.18,
                                                              ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Center(
                                                      child: Text(
                                                        'OFF',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color:
                                                              _autoStopEnabled
                                                              ? AppTheme
                                                                    .textSecondary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.55,
                                                                    )
                                                              : AppTheme
                                                                    .textDark,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Center(
                                                      child: Text(
                                                        'ON',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color:
                                                              _autoStopEnabled
                                                              ? Colors.white
                                                              : AppTheme
                                                                    .textSecondary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.6,
                                                                    ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom:
                                        switchTop +
                                        toggleHeight +
                                        labelBottomGap,
                                    child: const Text(
                                      '음성 인식 자동 종료',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _statusText(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: _statusColor(),
                fontWeight: _voiceStage == _FreeTalkVoiceStage.listening
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
