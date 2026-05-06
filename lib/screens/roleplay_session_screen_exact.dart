import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../core/audio/conversation_audio_session.dart';
import '../core/statistics/learning_activity_recorder.dart';
import '../feature/roleplay/roleplay_api.dart';
import '../feature/roleplay/roleplay_models.dart';
import '../feature/roleplay/roleplay_tts_player.dart';
import 'roleplay_scenarios_exact.dart';
import 'theme.dart';

class RoleplaySessionScreenExact extends StatefulWidget {
  const RoleplaySessionScreenExact({
    super.key,
    required this.scenario,
    required this.showSubtitles,
  });

  final RoleplayScenarioExact scenario;
  final bool showSubtitles;

  @override
  State<RoleplaySessionScreenExact> createState() =>
      _RoleplaySessionScreenExactState();
}

class _RoleplaySessionScreenExactState
    extends State<RoleplaySessionScreenExact> {
  final RoleplayApi _api = RoleplayApi();
  final ConversationAudioSession _audioSession = ConversationAudioSession();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<RoleplayChatMessage> _messages = <RoleplayChatMessage>[];

  RoleplayTtsPlayer? _ttsPlayer;
  AudioRecorder? _recorder;

  String? _sessionId;
  String? _stageTitle;
  String? _objectiveKo;
  String? _hintEn;
  String? _errorMessage;
  String? _lastAssistantText;

  bool _isStarting = true;
  bool _isSending = false;
  bool _isRecording = false;
  bool _isTranscribing = false;
  bool _isComplete = false;
  bool _autoPlayAiVoice = true;
  bool _isTtsAvailable = true;
  DateTime? _sessionStartedAt;

  @override
  void initState() {
    super.initState();
    _sessionStartedAt = DateTime.now();
    _startSession();
  }

  @override
  void dispose() {
    final startedAt = _sessionStartedAt;
    if (startedAt != null && _sessionId != null) {
      unawaited(
        LearningActivityRecorder.recordRoleplay(
          durationSec: DateTime.now().difference(startedAt).inSeconds,
          scenario: widget.scenario,
          completed: _isComplete,
          userTurnCount: _messages.where((message) => message.isUser).length,
        ),
      );
    }
    _textController.dispose();
    _scrollController.dispose();
    unawaited(_disposeRecorder());
    unawaited(_ttsPlayer?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  bool get _isBusy => _isStarting || _isSending || _isTranscribing;

  String get _difficultyCode {
    switch (widget.scenario.difficulty) {
      case '중급':
        return 'intermediate';
      case '고급':
        return 'advanced';
      default:
        return 'beginner';
    }
  }

  Future<void> _startSession() async {
    setState(() {
      _isStarting = true;
      _errorMessage = null;
      _messages.clear();
      _sessionId = null;
      _isComplete = false;
    });

    try {
      final result = await _api.startSession(
        scenarioId: widget.scenario.id,
        difficulty: _difficultyCode,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = result.sessionId;
        _applyResultToState(result);
        _appendAssistantMessage(result);
        _isStarting = false;
      });
      await _autoPlayIfNeeded(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _errorMessage = '롤플레잉을 시작하지 못했습니다. ($error)';
      });
    }
  }

  void _applyResultToState(RoleplayGenerateResult result) {
    _stageTitle = result.currentStageTitle;
    _objectiveKo = result.currentObjectiveKo;
    _hintEn = result.hintEn;
    _isComplete = result.sessionComplete;
    _lastAssistantText = result.ttsText ?? result.assistantUtterance;
  }

  void _appendAssistantMessage(RoleplayGenerateResult result) {
    final text = result.assistantUtterance.trim();
    if (text.isEmpty) return;
    _messages.add(
      RoleplayChatMessage(
        isUser: false,
        text: text,
        isRedirect: result.shouldRedirect,
      ),
    );
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _submitText() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sessionId == null || _isBusy || _isComplete) {
      return;
    }
    _textController.clear();
    await _sendUserInput(text: text, inputSource: 'text');
  }

  Future<void> _sendUserInput({
    required String text,
    required String inputSource,
  }) async {
    await _ttsPlayer?.stop();
    setState(() {
      _errorMessage = null;
      _isSending = true;
      _messages.add(RoleplayChatMessage(isUser: true, text: text));
    });
    _scrollToBottom();

    try {
      final result = await _api.continueSession(
        sessionId: _sessionId!,
        scenarioId: widget.scenario.id,
        difficulty: _difficultyCode,
        userInput: text,
        inputSource: inputSource,
      );
      if (!mounted) return;
      setState(() {
        _applyResultToState(result);
        _appendAssistantMessage(result);
        _isSending = false;
      });
      await _autoPlayIfNeeded(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _errorMessage = '응답을 받아오지 못했습니다. 다시 시도해 주세요.';
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecordingAndSend();
      return;
    }
    if (_isBusy || _sessionId == null || _isComplete) {
      return;
    }

    final micPermission = await Permission.microphone.request();
    if (!micPermission.isGranted) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '마이크 권한이 필요합니다. 설정에서 허용해 주세요.';
      });
      if (micPermission.isPermanentlyDenied) {
        await openAppSettings();
      }
      return;
    }

    await _ttsPlayer?.stop();

    final recorder = await _createFreshRecorder();
    final tempDir = await getTemporaryDirectory();
    final filePath = p.join(
      tempDir.path,
      'roleplay_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    try {
      await _audioSession.prepareForRecording();
      await _startRecorderWithRecovery(recorder, filePath);
    } catch (_) {
      await _disposeRecorder();
      await _audioSession.deactivate();
      if (!mounted) return;
      setState(() {
        _errorMessage = '녹음을 시작할 수 없습니다. 다시 시도해 주세요.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _errorMessage = null;
      _isRecording = true;
    });
  }

  Future<void> _stopRecordingAndSend() async {
    setState(() {
      _isRecording = false;
      _isTranscribing = true;
      _errorMessage = null;
    });

    String? savedPath;
    try {
      final recorder = _recorder;
      if (recorder == null) {
        throw Exception('missing recorder');
      }
      savedPath = await recorder.stop();
      await _disposeRecorder();
      if (savedPath == null) {
        throw Exception('missing file');
      }
      final transcription = await _api.transcribeAudio(File(savedPath));
      if (!mounted) return;
      if (transcription.error == 'mic_input_unstable') {
        setState(() {
          _isTranscribing = false;
          _errorMessage = '마이크 입력이 불안정합니다. 다시 시도해 주세요.';
        });
        return;
      }
      if (!transcription.hasTranscript) {
        setState(() {
          _isTranscribing = false;
          _errorMessage = '음성이 인식되지 않았습니다. 다시 말해 주세요.';
        });
        return;
      }

      setState(() {
        _isTranscribing = false;
      });
      await _sendUserInput(
        text: transcription.transcript!.trim(),
        inputSource: 'voice',
      );
    } catch (_) {
      await _disposeRecorder();
      if (!mounted) return;
      setState(() {
        _isTranscribing = false;
        _errorMessage = '음성 처리에 실패했습니다. 텍스트 입력이나 다시 녹음을 시도해 주세요.';
      });
    } finally {
      if (savedPath != null) {
        final file = File(savedPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
  }

  Future<void> _replayAssistantVoice() async {
    final text = _lastAssistantText?.trim();
    if (text == null || text.isEmpty || !_isTtsAvailable) {
      return;
    }
    await _playTts(text);
  }

  Future<void> _autoPlayIfNeeded(RoleplayGenerateResult result) async {
    final text = (result.ttsText ?? result.assistantUtterance).trim();
    if (!_autoPlayAiVoice || text.isEmpty) {
      return;
    }
    await _playTts(text);
  }

  Future<void> _playTts(String text) async {
    try {
      await _audioSession.prepareForPlayback();
      final bytes = await _api.fetchTts(
        text: text,
        voice: 'nova',
        model: 'gpt-4o-mini-tts',
        speed: 1.0,
      );
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        setState(() {
          _isTtsAvailable = false;
        });
        return;
      }

      _ttsPlayer ??= JustAudioRoleplayTtsPlayer();
      await _ttsPlayer!.play(bytes);
      if (!mounted) return;
      setState(() {
        _isTtsAvailable = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isTtsAvailable = false;
      });
    }
  }

  Future<AudioRecorder> _createFreshRecorder() async {
    await _disposeRecorder();
    final recorder = AudioRecorder();
    _recorder = recorder;
    return recorder;
  }

  Future<void> _disposeRecorder() async {
    final recorder = _recorder;
    _recorder = null;
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

  Future<void> _startRecorderWithRecovery(
    AudioRecorder recorder,
    String filePath,
  ) async {
    const config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
      bitRate: 128000,
    );
    try {
      await recorder.start(config, path: filePath);
    } catch (_) {
      await _disposeRecorder();
      final freshRecorder = await _createFreshRecorder();
      await freshRecorder.start(config, path: filePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardVisible = bottomInset > 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: widget.showSubtitles
          ? Colors.black
          : AppTheme.backgroundLight,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              widget.scenario.backgroundAsset,
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: widget.showSubtitles
                  ? Colors.black.withValues(alpha: 0.58)
                  : Colors.white.withValues(alpha: 0.84),
            ),
          ),
          Positioned.fill(
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: widget.showSubtitles
                  ? _buildSubtitleLayout(
                      context,
                      keyboardVisible: keyboardVisible,
                    )
                  : _buildVoiceLayout(
                      context,
                      keyboardVisible: keyboardVisible,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitleLayout(
    BuildContext context, {
    required bool keyboardVisible,
  }) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                _buildCircleButton(
                  icon: Icons.arrow_back,
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(width: 12),
                Expanded(child: _buildTopSummaryCard(isDark: true)),
                const SizedBox(width: 12),
                _buildCircleButton(
                  icon: _autoPlayAiVoice ? Icons.volume_up : Icons.volume_off,
                  onTap: () {
                    setState(() {
                      _autoPlayAiVoice = !_autoPlayAiVoice;
                    });
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: keyboardVisible ? 12 : 20),
          if (!keyboardVisible) ...[
            _buildTutorBadge(isDark: true),
            const SizedBox(height: 20),
          ],
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '대화 자막',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _objectiveKo ?? '서버에서 현재 학습 목표를 불러오는 중입니다.',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _buildMessagesPanel()),
                  _buildComposerCard(isDark: false, compact: keyboardVisible),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceLayout(
    BuildContext context, {
    required bool keyboardVisible,
  }) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(bottom: keyboardVisible ? 12 : 0),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                child: Column(
                  mainAxisAlignment: keyboardVisible
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.spaceBetween,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          _buildCircleButton(
                            icon: Icons.arrow_back,
                            background: Colors.white.withValues(alpha: 0.78),
                            foreground: AppTheme.textDark,
                            onTap: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: _buildTopSummaryCard(isDark: false)),
                          const SizedBox(width: 12),
                          _buildCircleButton(
                            icon: _autoPlayAiVoice
                                ? Icons.volume_up
                                : Icons.volume_off,
                            background: Colors.white.withValues(alpha: 0.78),
                            foreground: AppTheme.textDark,
                            onTap: () {
                              setState(() {
                                _autoPlayAiVoice = !_autoPlayAiVoice;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    if (keyboardVisible) const SizedBox(height: 18),
                    if (!keyboardVisible) ...[
                      _buildTutorBadge(isDark: false),
                      const SizedBox(height: 24),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildVoiceFocusCard(compact: keyboardVisible),
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: _buildComposerCard(
                        isDark: true,
                        compact: keyboardVisible,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopSummaryCard({required bool isDark}) {
    final textColor = isDark ? Colors.white : AppTheme.textDark;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.8)
        : AppTheme.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.42)
            : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.scenario.sceneTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _stageTitle ?? '세션 시작 중...',
            style: TextStyle(fontSize: 13, color: subColor),
          ),
        ],
      ),
    );
  }

  Widget _buildTutorBadge({required bool isDark}) {
    return Column(
      children: [
        Container(
          width: 116,
          height: 116,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.76),
            border: Border.all(color: AppTheme.primary, width: 4),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.25),
                blurRadius: 28,
                spreadRadius: 6,
              ),
            ],
          ),
          child: Icon(
            Icons.record_voice_over,
            size: 54,
            color: isDark ? Colors.white : AppTheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.42)
                : Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Tutor Chloe',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppTheme.textDark,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceFocusCard({required bool compact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _isComplete ? '시나리오 완료' : '현재 연습 포인트',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              if (_isRecording)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'REC',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _objectiveKo ?? '롤플레잉을 시작하는 중입니다.',
            style: const TextStyle(
              fontSize: 16,
              height: 1.5,
              color: AppTheme.textDark,
            ),
          ),
          SizedBox(height: compact ? 12 : 16),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(compact ? 12 : 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F7FB),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: Text(
              _hintEn ?? 'Listen carefully and answer in English.',
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 16),
            Text(
              _isComplete
                  ? '대화가 끝났습니다. 다시 듣기나 새 시나리오를 선택할 수 있습니다.'
                  : _statusText,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessagesPanel() {
    if (_isStarting) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildErrorBanner(),
          ),
        Expanded(
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _messages.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final message = _messages[index];
              return _buildMessageBubble(message);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(RoleplayChatMessage message) {
    final isUser = message.isUser;
    final bubbleColor = isUser
        ? AppTheme.primary
        : message.isRedirect
        ? const Color(0xFFFFF1D6)
        : const Color(0xFFF3F4F6);
    final textColor = isUser ? Colors.white : AppTheme.textDark;

    return Row(
      mainAxisAlignment: isUser
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser) ...[
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary,
            ),
            child: const Icon(
              Icons.support_agent,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : 6),
                bottomRight: Radius.circular(isUser ? 6 : 18),
              ),
            ),
            child: Text(
              message.text,
              style: TextStyle(fontSize: 15, height: 1.45, color: textColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComposerCard({required bool isDark, required bool compact}) {
    final Color panelColor = isDark
        ? Colors.white.withValues(alpha: 0.86)
        : Colors.white;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        compact ? 10 : 12,
        16,
        compact ? 10 : 16,
      ),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: widget.showSubtitles
            ? BorderRadius.zero
            : BorderRadius.circular(28),
        border: Border.all(
          color: widget.showSubtitles
              ? Colors.transparent
              : AppTheme.borderLight,
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.showSubtitles && _errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildErrorBanner(),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    enabled: !_isBusy && !_isRecording && !_isComplete,
                    minLines: 1,
                    maxLines: compact ? 2 : 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitText(),
                    decoration: InputDecoration(
                      hintText: '영어로 답변을 입력하세요',
                      filled: true,
                      fillColor: const Color(0xFFF6F7F8),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _buildIconAction(
                  icon: Icons.send,
                  label: '전송',
                  active: !_isBusy && !_isComplete,
                  compact: compact,
                  onTap: _submitText,
                ),
              ],
            ),
            SizedBox(height: compact ? 10 : 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildIconAction(
                  icon: Icons.replay,
                  label: '다시 듣기',
                  active: _isTtsAvailable && _lastAssistantText != null,
                  compact: compact,
                  onTap: _replayAssistantVoice,
                ),
                SizedBox(width: compact ? 18 : 22),
                _buildMicAction(compact: compact),
                SizedBox(width: compact ? 18 : 22),
                _buildIconAction(
                  icon: Icons.stop_circle_outlined,
                  label: '종료',
                  active: true,
                  compact: compact,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMicAction({required bool compact}) {
    final bool active = !_isBusy && !_isComplete || _isRecording;
    return GestureDetector(
      onTap: active ? _toggleRecording : null,
      child: Container(
        width: compact ? 68 : 76,
        height: compact ? 68 : 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isRecording ? Colors.red : AppTheme.primary,
          boxShadow: [
            BoxShadow(
              color: (_isRecording ? Colors.red : AppTheme.primary).withValues(
                alpha: 0.28,
              ),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Icon(
          _isRecording ? Icons.stop : Icons.mic,
          color: Colors.white,
          size: compact ? 30 : 34,
        ),
      ),
    );
  }

  Widget _buildIconAction({
    required IconData icon,
    required String label,
    required bool active,
    required bool compact,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: active ? onTap : null,
      child: Opacity(
        opacity: active ? 1 : 0.45,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 44 : 48,
              height: compact ? 44 : 48,
              decoration: const BoxDecoration(
                color: Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: AppTheme.textSecondary,
                size: compact ? 22 : 24,
              ),
            ),
            SizedBox(height: compact ? 3 : 4),
            Text(
              label,
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? background,
    Color? foreground,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background ?? Colors.black.withValues(alpha: 0.42),
        ),
        child: Icon(icon, color: foreground ?? Colors.white, size: 22),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD0D0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
            ),
          ),
          if (_sessionId == null && !_isStarting)
            TextButton(onPressed: _startSession, child: const Text('다시 시도')),
        ],
      ),
    );
  }

  String get _statusText {
    if (_isStarting) {
      return '롤플레잉 세션을 시작하는 중입니다.';
    }
    if (_isRecording) {
      return '녹음 중입니다. 다시 누르면 전송합니다.';
    }
    if (_isTranscribing) {
      return '음성을 텍스트로 변환하는 중입니다.';
    }
    if (_isSending) {
      return 'AI 응답을 기다리는 중입니다.';
    }
    if (_isComplete) {
      return '설계된 시나리오가 완료되었습니다.';
    }
    return _autoPlayAiVoice ? 'AI 음성이 자동으로 재생됩니다.' : 'AI 음성 자동 재생이 꺼져 있습니다.';
  }
}
