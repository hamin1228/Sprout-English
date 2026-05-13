import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../core/auth/auth_controller.dart';
import '../core/network/server_config.dart';
import '../core/settings/app_settings.dart';
import '../core/settings/app_settings_store.dart';
import 'profile_settings_screen_exact.dart';
import 'server_connection_test_screen.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _appVersion = '1.0.0+1';

  final AppSettingsStore _store = AppSettingsStore.instance;
  AppSettings? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final settings = await _store.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _saveUpdatedSettings(
    AppSettings Function(AppSettings current) transform,
  ) async {
    final current = _settings ?? await _store.load();
    final next = transform(current);
    if (mounted) {
      setState(() => _settings = next);
    }
    await _store.save(next);
  }

  String _difficultyLabel(String difficulty) {
    switch (difficulty) {
      case 'beginner':
        return '초급';
      case 'intermediate':
        return '중급';
      case 'advanced':
        return '상급';
      default:
        return '초급';
    }
  }

  String _languageLabel(String language) {
    switch (language) {
      case 'english':
        return '영어 중심';
      case 'korean':
      default:
        return '한국어 중심';
    }
  }

  Future<void> _pickReminderTime() async {
    final settings = _settings;
    if (settings == null || !settings.reminderEnabled) return;

    final parts = settings.reminderTime.split(':');
    final initialTime = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 20,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (picked == null) return;

    final nextValue =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    await _saveUpdatedSettings(
      (current) => current.copyWith(reminderTime: nextValue),
    );
  }

  Future<void> _pickDifficulty() async {
    final settings = _settings;
    if (settings == null) return;
    final picked = await _showChoiceSheet<String>(
      title: '기본 난이도',
      currentValue: settings.defaultDifficulty,
      options: const [
        _ChoiceOption(value: 'beginner', label: '초급'),
        _ChoiceOption(value: 'intermediate', label: '중급'),
        _ChoiceOption(value: 'advanced', label: '상급'),
      ],
    );
    if (picked == null) return;
    await _saveUpdatedSettings(
      (current) => current.copyWith(defaultDifficulty: picked),
    );
  }

  Future<void> _pickExplanationLanguage() async {
    final settings = _settings;
    if (settings == null) return;
    final picked = await _showChoiceSheet<String>(
      title: '설명 언어',
      currentValue: settings.explanationLanguage,
      options: const [
        _ChoiceOption(value: 'korean', label: '한국어 중심'),
        _ChoiceOption(value: 'english', label: '영어 중심'),
      ],
    );
    if (picked == null) return;
    await _saveUpdatedSettings(
      (current) => current.copyWith(explanationLanguage: picked),
    );
  }

  Future<T?> _showChoiceSheet<T>({
    required String title,
    required T currentValue,
    required List<_ChoiceOption<T>> options,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                for (final option in options)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(option.label),
                    trailing: option.value == currentValue
                        ? const Icon(
                            Icons.check_circle,
                            color: AppTheme.primary,
                          )
                        : const Icon(
                            Icons.circle_outlined,
                            color: AppTheme.textSecondary,
                          ),
                    onTap: () => Navigator.of(context).pop(option.value),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMicrophoneTestSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => const _MicrophoneTestSheet(),
    );
  }

  Future<void> _editServerUrl(AppSettings settings) async {
    final controller = TextEditingController(text: settings.serverBaseUrl);
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('서버 URL 설정'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'https://example.lhr.life',
              labelText: '서버 URL',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(''),
              child: const Text('초기화'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null) return;
    await _saveUpdatedSettings((current) => current.copyWith(serverBaseUrl: result));
    setServerBaseUrlOverride(result);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.isEmpty ? '서버 URL을 기본값으로 되돌렸습니다.' : '서버 URL을 저장했습니다: $result')),
    );
  }

  Future<void> _resetSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('설정 초기화'),
          content: const Text('모든 환경설정을 기본값으로 되돌릴까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('초기화'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    final resetSettings = await _store.reset();
    if (!mounted) return;
    setState(() => _settings = resetSettings);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('설정을 초기화했습니다.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: AppTheme.backgroundLight,
              elevation: 0,
              title: const Text(
                'Settings',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(_settings ?? const AppSettings()),
    );
  }

  Widget _buildContent(AppSettings settings) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, widget.showAppBar ? 12 : 20, 16, 24),
      children: [
        if (!widget.showAppBar) ...[
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 20),
        ],
        _SettingsSection(
          title: '계정',
          children: [
            _SettingsActionTile(
              title: '프로필 설정',
              subtitle: '프로필 사진과 이름을 관리합니다.',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ProfileSettingsScreenExact(),
                  ),
                );
              },
            ),
          ],
        ),
        _SettingsSection(
          title: '알림',
          children: [
            _SettingsToggleTile(
              switchKey: const ValueKey(AppSettingsStorageKeys.reminderEnabled),
              title: '학습 리마인더',
              subtitle: '하루 한 번 학습 알림을 받습니다.',
              value: settings.reminderEnabled,
              onChanged: (value) {
                _saveUpdatedSettings(
                  (current) => current.copyWith(reminderEnabled: value),
                );
              },
            ),
            _SettingsActionTile(
              tileKey: const ValueKey('reminder_time_tile'),
              title: '알림 시간',
              subtitle: settings.reminderEnabled
                  ? '매일 알림을 보낼 기준 시간을 정합니다.'
                  : '학습 리마인더를 켜면 시간을 설정할 수 있습니다.',
              value: settings.reminderTime,
              onTap: settings.reminderEnabled ? _pickReminderTime : null,
            ),
            _SettingsToggleTile(
              switchKey: const ValueKey(
                AppSettingsStorageKeys.streakReminderEnabled,
              ),
              title: '연속 학습 끊김 알림',
              subtitle: '며칠 동안 학습이 없을 때 다시 알려줍니다.',
              value: settings.streakReminderEnabled,
              onChanged: (value) {
                _saveUpdatedSettings(
                  (current) => current.copyWith(streakReminderEnabled: value),
                );
              },
            ),
          ],
        ),
        _SettingsSection(
          title: '학습 기본값',
          children: [
            _SettingsActionTile(
              title: '기본 난이도',
              subtitle: '새 학습 화면에서 먼저 선택될 난이도입니다.',
              value: _difficultyLabel(settings.defaultDifficulty),
              onTap: _pickDifficulty,
            ),
            _SettingsToggleTile(
              switchKey: const ValueKey(
                AppSettingsStorageKeys.roleplaySubtitleDefault,
              ),
              title: '롤플레잉 자막 기본값',
              subtitle: '롤플레잉 진입 시 자막 표시 여부를 기본 설정합니다.',
              value: settings.roleplaySubtitleDefault,
              onChanged: (value) {
                _saveUpdatedSettings(
                  (current) => current.copyWith(roleplaySubtitleDefault: value),
                );
              },
            ),
            _SettingsActionTile(
              title: '설명 언어',
              subtitle: '문장 설명과 안내 문구의 우선 언어를 정합니다.',
              value: _languageLabel(settings.explanationLanguage),
              onTap: _pickExplanationLanguage,
            ),
          ],
        ),
        _SettingsSection(
          title: '음성 · 대화',
          children: [
            _SettingsToggleTile(
              switchKey: const ValueKey(AppSettingsStorageKeys.aiVoiceAutoplay),
              title: 'AI 음성 자동 재생',
              subtitle: 'AI 응답이 도착하면 음성을 자동으로 재생합니다.',
              value: settings.aiVoiceAutoplay,
              onChanged: (value) {
                _saveUpdatedSettings(
                  (current) => current.copyWith(aiVoiceAutoplay: value),
                );
              },
            ),
            _SettingsToggleTile(
              switchKey: const ValueKey(AppSettingsStorageKeys.silenceAutoStop),
              title: '무음 시 자동 종료',
              subtitle: '프리토킹 녹음 중 침묵이 길어지면 자동으로 종료합니다.',
              value: settings.silenceAutoStop,
              onChanged: (value) {
                _saveUpdatedSettings(
                  (current) => current.copyWith(silenceAutoStop: value),
                );
              },
            ),
            _SettingsActionTile(
              title: '마이크 테스트',
              subtitle: '권한 상태를 확인하고 음성 입력 준비를 점검합니다.',
              onTap: _showMicrophoneTestSheet,
            ),
          ],
        ),
        _SettingsSection(
          title: '서버 연결',
          children: [
            _SettingsActionTile(
              title: '서버 URL',
              subtitle: settings.serverBaseUrl.isNotEmpty
                  ? settings.serverBaseUrl
                  : '기본값 사용 (컴파일 시 설정)',
              onTap: () => _editServerUrl(settings),
            ),
            _SettingsActionTile(
              title: '서버 연결 테스트',
              subtitle: 'Vercel API 서버 연결 상태를 확인합니다.',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ServerConnectionTestScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        _SettingsSection(
          title: '앱',
          children: [
            const _SettingsActionTile(
              title: '앱 버전',
              subtitle: '현재 설치된 앱 버전 정보입니다.',
              value: _appVersion,
            ),
            _SettingsActionTile(
              title: '설정 초기화',
              subtitle: '저장된 환경설정을 모두 기본값으로 되돌립니다.',
              titleColor: Color(0xFFD14343),
              onTap: _resetSettings,
            ),
            Consumer(
              builder: (context, ref, _) => _SettingsActionTile(
                title: '로그아웃',
                subtitle: '현재 계정에서 로그아웃합니다.',
                titleColor: Color(0xFFD14343),
                onTap: () async {
                  await ref.read(authControllerProvider.notifier).logout();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChoiceOption<T> {
  const _ChoiceOption({required this.value, required this.label});

  final T value;
  final String label;
}

String _microphonePermissionLabel(PermissionStatus status) {
  if (status.isGranted) return '허용됨';
  if (status.isPermanentlyDenied) return '영구 거부';
  if (status.isDenied) return '거부됨';
  return '확인 필요';
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppTheme.borderLight,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.title,
    required this.subtitle,
    this.value,
    this.onTap,
    this.titleColor,
    this.tileKey,
  });

  final String title;
  final String subtitle;
  final String? value;
  final VoidCallback? onTap;
  final Color? titleColor;
  final Key? tileKey;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: tileKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: enabled
                            ? (titleColor ?? AppTheme.textDark)
                            : AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: enabled
                            ? AppTheme.textSecondary
                            : AppTheme.textSecondary.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (value != null)
                Text(
                  value!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: enabled
                        ? AppTheme.textSecondary
                        : AppTheme.textSecondary.withValues(alpha: 0.72),
                  ),
                ),
              if (enabled) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  color: AppTheme.textSecondary,
                  size: 22,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsToggleTile extends StatelessWidget {
  const _SettingsToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.switchKey,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Key switchKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            key: switchKey,
            value: value,
            activeThumbColor: AppTheme.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _MicrophoneTestSheet extends StatefulWidget {
  const _MicrophoneTestSheet();

  @override
  State<_MicrophoneTestSheet> createState() => _MicrophoneTestSheetState();
}

class _MicrophoneTestSheetState extends State<_MicrophoneTestSheet> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<Amplitude>? _amplitudeSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  Timer? _recordingTimer;

  PermissionStatus _permissionStatus = PermissionStatus.denied;
  String? _recordedPath;
  DateTime? _recordingStartedAt;
  Duration _recordingDuration = Duration.zero;
  double _inputLevel = 0.02;
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bindPlayerState();
    unawaited(_loadPermissionStatus());
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    unawaited(_amplitudeSubscription?.cancel() ?? Future<void>.value());
    unawaited(_playerStateSubscription?.cancel() ?? Future<void>.value());
    unawaited(_disposeRecorder());
    unawaited(_disposePlayer());
    final recordedPath = _recordedPath;
    if (recordedPath != null) {
      unawaited(_deleteFile(recordedPath));
    }
    super.dispose();
  }

  Future<void> _loadPermissionStatus() async {
    final status = await Permission.microphone.status;
    if (!mounted) return;
    setState(() => _permissionStatus = status);
  }

  void _bindPlayerState() {
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying =
            state.playing && state.processingState != ProcessingState.completed;
      });
    });
  }

  Future<void> _requestPermission() async {
    if (_permissionStatus.isPermanentlyDenied) {
      await openAppSettings();
      await _loadPermissionStatus();
      return;
    }

    final nextStatus = await Permission.microphone.request();
    if (!mounted) return;
    setState(() => _permissionStatus = nextStatus);
  }

  Future<void> _toggleRecording() async {
    if (_busy) return;
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!_permissionStatus.isGranted) {
      await _requestPermission();
      if (!_permissionStatus.isGranted) {
        return;
      }
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      setState(() => _permissionStatus = PermissionStatus.denied);
      return;
    }

    setState(() => _busy = true);

    await _player.stop();
    await _deleteRecordedFile();

    final directory = await getTemporaryDirectory();
    final filePath =
        '${directory.path}/mic_test_${DateTime.now().millisecondsSinceEpoch}.m4a';

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: filePath,
      );

      _recordingTimer?.cancel();
      _recordingStartedAt = DateTime.now();
      _recordingDuration = Duration.zero;
      _inputLevel = 0.06;
      _recordedPath = filePath;
      _isRecording = true;

      _amplitudeSubscription?.cancel();
      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((amplitude) {
            if (!mounted) return;
            setState(() {
              _inputLevel = _normalizeAmplitude(amplitude.current);
            });
          });
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (!mounted || _recordingStartedAt == null) return;
        setState(() {
          _recordingDuration = DateTime.now().difference(_recordingStartedAt!);
        });
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('녹음을 시작하지 못했습니다: $error')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stopRecording() async {
    setState(() => _busy = true);
    try {
      final stoppedPath = await _recorder.stop();
      _recordingTimer?.cancel();
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordedPath = stoppedPath ?? _recordedPath;
        _inputLevel = 0.02;
        if (_recordingStartedAt != null) {
          _recordingDuration = DateTime.now().difference(_recordingStartedAt!);
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('녹음을 종료하지 못했습니다: $error')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _togglePlayback() async {
    final recordedPath = _recordedPath;
    if (recordedPath == null || _isRecording || _busy) return;

    if (_isPlaying) {
      await _player.stop();
      if (!mounted) return;
      setState(() => _isPlaying = false);
      return;
    }

    setState(() => _busy = true);
    try {
      await _player.setFilePath(recordedPath);
      await _player.play();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('재생하지 못했습니다: $error')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _deleteRecordedFile() async {
    final recordedPath = _recordedPath;
    _recordedPath = null;
    if (recordedPath == null) return;
    await _deleteFile(recordedPath);
  }

  Future<void> _deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _disposeRecorder() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {
      // ignore recorder teardown errors
    }
    try {
      await _recorder.dispose();
    } catch (_) {
      // ignore recorder teardown errors
    }
  }

  Future<void> _disposePlayer() async {
    try {
      await _player.dispose();
    } catch (_) {
      // ignore player teardown errors
    }
  }

  double _normalizeAmplitude(double db) {
    if (!db.isFinite) {
      return 0.02;
    }
    return ((db + 45) / 45).clamp(0.02, 1.0).toDouble();
  }

  String _helperText() {
    if (_permissionStatus.isGranted) {
      if (_isRecording) {
        return '지금 실제 마이크 입력을 녹음하고 있습니다. 짧게 말한 뒤 녹음을 종료해 보세요.';
      }
      if (_recordedPath != null) {
        return '녹음이 완료되었습니다. 바로 재생해서 입력과 출력이 정상인지 확인할 수 있습니다.';
      }
      return '권한이 허용되어 있습니다. 녹음을 시작한 뒤 실제로 말해 보고 재생해서 확인하세요.';
    }
    if (_permissionStatus.isPermanentlyDenied) {
      return '마이크 권한이 영구 거부되어 있습니다. 기기 설정에서 권한을 허용해야 테스트를 진행할 수 있습니다.';
    }
    if (_permissionStatus.isDenied) {
      return '마이크 권한을 허용한 뒤 실제 녹음 테스트를 진행할 수 있습니다.';
    }
    return '권한 상태를 확인한 뒤 실제 녹음과 재생으로 마이크를 점검할 수 있습니다.';
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final canRecord = _permissionStatus.isGranted && !_busy;
    final canPlay =
        _recordedPath != null &&
        !_isRecording &&
        !_busy &&
        _permissionStatus.isGranted;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '마이크 테스트',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '현재 권한 상태: ${_microphonePermissionLabel(_permissionStatus)}',
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _helperText(),
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isRecording
                        ? '녹음 중'
                        : _isPlaying
                        ? '재생 중'
                        : _recordedPath != null
                        ? '재생 준비 완료'
                        : '대기 중',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 10,
                      value: _isRecording
                          ? _inputLevel
                          : (_isPlaying ? 0.55 : 0.06),
                      backgroundColor: Colors.white,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isRecording
                        ? '실시간 입력 레벨이 표시됩니다.'
                        : _recordedPath != null
                        ? '최근 녹음 길이 ${_formatDuration(_recordingDuration)}'
                        : '아직 녹음된 파일이 없습니다.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('닫기'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _requestPermission,
                    child: Text(
                      _permissionStatus.isPermanentlyDenied ? '설정 열기' : '권한 확인',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canRecord ? _toggleRecording : null,
                    icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                    label: Text(_isRecording ? '녹음 종료' : '녹음 시작'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canPlay ? _togglePlayback : null,
                    icon: Icon(
                      _isPlaying ? Icons.stop_circle : Icons.play_arrow,
                    ),
                    label: Text(_isPlaying ? '재생 중지' : '재생'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
