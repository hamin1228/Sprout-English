import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/settings/app_settings_store.dart';
import '../../core/statistics/learning_activity_recorder.dart';
import '../../screens/theme.dart';
import 'models/toeic_writing_models.dart';
import 'services/toeic_writing_api.dart';

enum ToeicWritingPhase { setup, practice, result }

class ToeicWritingPage extends StatefulWidget {
  const ToeicWritingPage({super.key});

  @override
  State<ToeicWritingPage> createState() => _ToeicWritingPageState();
}

class _ToeicWritingPageState extends State<ToeicWritingPage> {
  final ToeicWritingApi _api = ToeicWritingApi();
  final TextEditingController _textController = TextEditingController();

  ToeicWritingPhase _phase = ToeicWritingPhase.setup;
  ToeicWritingTaskType _taskType = ToeicWritingTaskType.picture;
  ToeicWritingLevel _level = ToeicWritingLevel.beginner;
  ToeicWritingPrompt? _prompt;
  ToeicWritingEvaluation? _evaluation;
  bool _loading = false;
  bool _saveResult = false;
  String? _error;

  DateTime? _startedAt;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    final settings = await AppSettingsStore.instance.load();
    if (!mounted) return;
    setState(() {
      _level = switch (settings.defaultDifficulty) {
        'intermediate' => ToeicWritingLevel.intermediate,
        'advanced' => ToeicWritingLevel.advanced,
        _ => ToeicWritingLevel.beginner,
      };
    });
  }

  int get _elapsedSec {
    if (_startedAt == null) return 0;
    return DateTime.now().difference(_startedAt!).inSeconds;
  }

  bool get _canSubmit {
    final prompt = _prompt;
    if (prompt == null || _loading) return false;
    return _textController.text.trim().isNotEmpty;
  }

  Future<void> _startPractice() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _evaluation = null;
    });

    try {
      final prompt = await _api.fetchPrompt(taskType: _taskType, level: _level);
      if (!mounted) return;
      _textController.clear();
      _startedAt = DateTime.now();
      setState(() {
        _prompt = prompt;
        _phase = ToeicWritingPhase.practice;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '문항을 불러오지 못했습니다.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit() async {
    final prompt = _prompt;
    if (prompt == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final evaluation = await _api.evaluate(
        prompt: prompt,
        elapsedSec: _elapsedSec,
        save: _saveResult,
        text: _textController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _evaluation = evaluation;
        _phase = ToeicWritingPhase.result;
      });
      await LearningActivityRecorder.recordToeicWriting(
        durationSec: _elapsedSec,
        taskType: _taskType,
        level: _level,
        evaluation: evaluation,
      );
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(error));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_error ?? '제출 중 오류가 발생했습니다.')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _retrySamePrompt() {
    _startedAt = DateTime.now();
    setState(() {
      _evaluation = null;
      _phase = ToeicWritingPhase.practice;
    });
  }

  void _resetToSetup() {
    setState(() {
      _phase = ToeicWritingPhase.setup;
      _prompt = null;
      _evaluation = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundLight,
        elevation: 0,
        title: const Text(
          'TOEIC Writing',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: switch (_phase) {
            ToeicWritingPhase.setup => _buildSetupView(),
            ToeicWritingPhase.practice => _buildPracticeView(),
            ToeicWritingPhase.result => _buildResultView(),
          },
        ),
      ),
    );
  }

  Widget _buildSetupView() {
    return ListView(
      key: const ValueKey<String>('setup'),
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '실전 유형 선택',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'TOEIC Writing에서 자주 나오는 3가지 유형을 같은 흐름으로 연습합니다. 먼저 유형과 난이도를 고른 뒤 문제를 불러오세요.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              ...ToeicWritingTaskType.values.map(_buildTaskTile),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('난이도 선택'),
        const SizedBox(height: 10),
        Row(
          children: ToeicWritingLevel.values
              .map(
                (level) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: level == ToeicWritingLevel.advanced ? 0 : 10,
                    ),
                    child: _LevelChip(
                      label: level.label,
                      selected: _level == level,
                      onTap: () => setState(() => _level = level),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('선택한 트랙'),
        const SizedBox(height: 10),
        _PreviewCard(taskType: _taskType, level: _level),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '결과 저장',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '제출 결과를 서버에 저장해 record_id를 발급합니다.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _saveResult,
                activeThumbColor: AppTheme.primary,
                onChanged: (value) => setState(() => _saveResult = value),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 28),
        SizedBox(
          height: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: _loading ? null : _startPractice,
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    '문항 시작',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPracticeView() {
    final prompt = _prompt;
    if (prompt == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      key: const ValueKey<String>('practice'),
      padding: const EdgeInsets.all(20),
      children: [
        _PhaseHeader(
          title: _phaseHeaderTitle(prompt),
          subtitle: '${_taskType.label} · ${_level.label}',
        ),
        const SizedBox(height: 18),
        if (_taskType == ToeicWritingTaskType.picture)
          _buildPicturePrompt(prompt)
        else
          _buildTextPrompt(prompt),
        const SizedBox(height: 18),
        _buildEditorCard(prompt),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _loading ? null : _startPractice,
                child: const Text('새 문제'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _canSubmit ? _submit : null,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('제출하고 피드백 보기'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultView() {
    final prompt = _prompt;
    final evaluation = _evaluation;
    if (prompt == null || evaluation == null) {
      return const SizedBox.shrink();
    }

    return ListView(
      key: const ValueKey<String>('result'),
      padding: const EdgeInsets.all(20),
      children: [
        _PhaseHeader(
          title: '결과 리포트',
          subtitle: '${prompt.title} · ${_taskType.label}',
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${evaluation.overallScore}',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '연습용 종합 점수',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          evaluation.recordId == null
                              ? '루브릭과 모범답안을 기준으로 다음 연습 방향을 정리했습니다.'
                              : 'record_id ${evaluation.recordId} 로 결과가 저장되었습니다.',
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ...evaluation.rubric.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RubricCard(item: item),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '모범답안',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                evaluation.modelAnswer,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SimpleListCard(
          title: '오답 분석',
          items: evaluation.contentAnalysis.isEmpty
              ? const <String>['핵심 내용은 대체로 잘 반영했습니다.']
              : evaluation.contentAnalysis,
        ),
        const SizedBox(height: 12),
        _PointSummaryCard(
          matchedPoints: evaluation.matchedPoints,
          missingPoints: evaluation.missingPoints,
        ),
        const SizedBox(height: 12),
        _SimpleListCard(
          title: '정답에 더 가깝게 쓰는 방법',
          items: evaluation.betterAnswerTips.isEmpty
              ? const <String>['required points를 먼저 체크한 뒤 문장을 정리해 보세요.']
              : evaluation.betterAnswerTips,
        ),
        const SizedBox(height: 12),
        _SimpleListCard(
          title: '문법 피드백',
          items: evaluation.grammarFeedback.isEmpty
              ? const <String>['문법상 큰 문제는 두드러지지 않습니다.']
              : evaluation.grammarFeedback,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _retrySamePrompt,
                child: const Text('같은 문제 다시'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                ),
                onPressed: _resetToSetup,
                child: const Text('다른 문제 풀기'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPicturePrompt(ToeicWritingPrompt prompt) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _picturePromptLabel(prompt),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              color: const Color(0xFFF5F7FB),
              child: AspectRatio(
                aspectRatio: 1.35,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: _buildPromptImage(prompt.imageAsset!),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _localizedInstruction(prompt),
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextPrompt(ToeicWritingPrompt prompt) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prompt.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 12),
          if ((prompt.sourceText ?? '').isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                prompt.sourceText!,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: AppTheme.textDark,
                ),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            _localizedInstruction(prompt),
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          ..._localizedRequiredPoints(prompt).map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorCard(ToeicWritingPrompt prompt) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '답안 작성',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            minLines: _taskType == ToeicWritingTaskType.picture ? 8 : 10,
            maxLines: _taskType == ToeicWritingTaskType.picture ? 12 : 14,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              hintText: _editorHintText(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskTile(ToeicWritingTaskType taskType) {
    final selected = _taskType == taskType;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => setState(() => _taskType = taskType),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected
                ? taskType.accentColor.withValues(alpha: 0.08)
                : AppTheme.backgroundLight,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? taskType.accentColor : AppTheme.borderLight,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: taskType.accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(taskType.icon, color: taskType.accentColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      taskType.label,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      taskType.subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? taskType.accentColor : AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.0,
        color: AppTheme.textSecondary,
      ),
    );
  }

  String _errorMessage(DioException error) {
    final detail = error.response?.data;
    if (detail is Map && detail['detail'] != null) {
      return detail['detail'].toString();
    }
    final uri = error.requestOptions.uri.toString();
    switch (error.type) {
      case DioExceptionType.connectionError:
        return '서버에 연결하지 못했습니다. 주소를 확인하세요: $uri';
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return '서버 요청 시간이 초과되었습니다: $uri';
      default:
        final message = error.message?.trim();
        if (message != null && message.isNotEmpty) {
          return '서버 요청 실패: $message';
        }
        return '서버 요청 중 오류가 발생했습니다: $uri';
    }
  }

  String _localizedInstruction(ToeicWritingPrompt prompt) {
    return switch (prompt.taskType) {
      ToeicWritingTaskType.picture =>
        '사진을 보고 보이는 상황을 영어로 자연스럽게 묘사하세요. 핵심 장면, 인물의 행동, 분위기가 드러나도록 한 번에 작성하면 됩니다.',
      ToeicWritingTaskType.email =>
        '아래 영어 메시지를 읽고 영어로 답장을 작성하세요. 문제에서 요구하는 핵심 사항을 빠뜨리지 말고, 정중한 답장 형식으로 쓰면 됩니다.',
      ToeicWritingTaskType.opinion =>
        '아래 영어 질문을 읽고 자신의 의견을 영어로 작성하세요. 입장을 먼저 밝히고, 이유와 예시를 이어서 전개하면 됩니다.',
    };
  }

  List<String> _localizedRequiredPoints(ToeicWritingPrompt prompt) {
    return switch (prompt.taskType) {
      ToeicWritingTaskType.picture => const <String>[
        '사진 속 인물, 장소, 행동이 드러나게 묘사하세요.',
        '문장을 나누어 써도 되고 한 단락으로 써도 됩니다.',
        '자연스러운 영어 문장 흐름을 우선하세요.',
      ],
      ToeicWritingTaskType.email => const <String>[
        '문제의 요청 사항을 모두 반영해 답장하세요.',
        '인사, 본문, 마무리의 흐름을 의식해 작성하세요.',
        '정중하고 명확한 표현을 사용하세요.',
      ],
      ToeicWritingTaskType.opinion => const <String>[
        '첫 부분에서 자신의 입장을 분명히 밝히세요.',
        '이유나 예시를 붙여 의견을 전개하세요.',
        '마지막 문장에서 의견을 다시 정리하세요.',
      ],
    };
  }

  String _editorHintText() {
    return switch (_taskType) {
      ToeicWritingTaskType.picture => '사진을 보고 보이는 상황을 영어로 한 번에 작성하세요.',
      ToeicWritingTaskType.email => '영어 답장을 작성하세요.',
      ToeicWritingTaskType.opinion => '영어 의견문을 작성하세요.',
    };
  }

  String _phaseHeaderTitle(ToeicWritingPrompt prompt) {
    if (_taskType == ToeicWritingTaskType.picture) {
      return 'Picture Description';
    }
    return prompt.title;
  }

  String _picturePromptLabel(ToeicWritingPrompt prompt) {
    switch (_level) {
      case ToeicWritingLevel.beginner:
        return 'Basic Scene Practice';
      case ToeicWritingLevel.intermediate:
        return 'Intermediate Scene Practice';
      case ToeicWritingLevel.advanced:
        return 'Advanced Scene Practice';
    }
  }

  Widget _buildPromptImage(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _ImageLoadFallback(path: path),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        },
      );
    }
    return Image.asset(
      path,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _ImageLoadFallback(path: path),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.taskType, required this.level});

  final ToeicWritingTaskType taskType;
  final ToeicWritingLevel level;

  @override
  Widget build(BuildContext context) {
    final checklist = switch (taskType) {
      ToeicWritingTaskType.picture => const <String>[
        '사진 전체 상황을 한 번에 묘사',
        '인물, 장소, 행동이 드러나게 작성',
        '자연스러운 문장 흐름 우선',
      ],
      ToeicWritingTaskType.email => const <String>[
        '필수 포인트 3개를 모두 반영',
        '정중한 인사말과 마무리 문구 포함',
        '요청과 질문을 분리해 작성',
      ],
      ToeicWritingTaskType.opinion => const <String>[
        '첫 문장에 입장을 분명히 제시',
        '이유와 예시를 연결 표현으로 확장',
        '마지막 문장에서 의견을 다시 정리',
      ],
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${taskType.label} · ${level.label}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            taskType.subtitle,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ...checklist.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.check_circle,
                      size: 14,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textDark,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.borderLight,
            width: selected ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: selected ? AppTheme.primary : AppTheme.textDark,
          ),
        ),
      ),
    );
  }
}

class _PhaseHeader extends StatelessWidget {
  const _PhaseHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RubricCard extends StatelessWidget {
  const _RubricCard({required this.item});

  final ToeicRubricItem item;

  @override
  Widget build(BuildContext context) {
    final ratio = item.score / item.maxScore;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              Text(
                '${item.score}/${item.maxScore}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: ratio,
              color: AppTheme.primary,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.feedback,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleListCard extends StatelessWidget {
  const _SimpleListCard({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderLight),
      ),
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
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(Icons.circle, size: 8, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PointSummaryCard extends StatelessWidget {
  const _PointSummaryCard({
    required this.matchedPoints,
    required this.missingPoints,
  });

  final List<String> matchedPoints;
  final List<String> missingPoints;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '핵심 포인트 비교',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '반영된 포인트',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          ...(matchedPoints.isEmpty
                  ? const <String>['직접적으로 반영된 핵심 포인트가 뚜렷하지 않습니다.']
                  : matchedPoints)
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Icon(
                          Icons.check_circle,
                          size: 16,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 10),
          const Text(
            '보완이 필요한 포인트',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          ...(missingPoints.isEmpty
                  ? const <String>['누락된 핵심 포인트는 많지 않습니다.']
                  : missingPoints)
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Icon(
                          Icons.error_outline,
                          size: 16,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _ImageLoadFallback extends StatelessWidget {
  const _ImageLoadFallback({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.backgroundLight,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Text(
        '이미지를 불러오지 못했습니다.\n$path',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          height: 1.5,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}
