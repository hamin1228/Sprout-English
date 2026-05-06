import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/server_config.dart';
import '../../core/settings/app_settings_store.dart';
import '../../core/statistics/learning_activity_recorder.dart';

enum VocabEntryMode { study, quiz }

enum VocabPhase { setup, memorizing, readyForQuiz, quiz }

class VocabSrsItem {
  final int cardId;
  final String lemma;
  final String meaningKo;
  final String? exampleEn;
  final int difficulty;
  final String direction;

  VocabSrsItem({
    required this.cardId,
    required this.lemma,
    required this.meaningKo,
    required this.exampleEn,
    required this.difficulty,
    required this.direction,
  });

  factory VocabSrsItem.fromJson(Map<String, dynamic> j) {
    return VocabSrsItem(
      cardId: j['card_id'] as int,
      lemma: j['lemma'] as String,
      meaningKo: j['meaning_ko'] as String,
      exampleEn: j['example_en'] as String?,
      difficulty: j['difficulty'] as int,
      direction: j['direction'] as String,
    );
  }
}

class VocabMcqItem {
  final int cardId;
  final String questionText;
  final List<String> choices;
  final int answerIndex;
  final String direction;

  VocabMcqItem({
    required this.cardId,
    required this.questionText,
    required this.choices,
    required this.answerIndex,
    required this.direction,
  });

  factory VocabMcqItem.fromJson(Map<String, dynamic> j) {
    return VocabMcqItem(
      cardId: j['card_id'] as int,
      questionText: j['question_text'] as String,
      choices: (j['choices'] as List).map((e) => e.toString()).toList(),
      answerIndex: j['answer_index'] as int,
      direction: j['direction'] as String,
    );
  }
}

class VocabPage extends StatefulWidget {
  const VocabPage({super.key, this.entryMode = VocabEntryMode.study});

  final VocabEntryMode entryMode;

  @override
  State<VocabPage> createState() => _VocabPageState();
}

class _VocabPageState extends State<VocabPage> {
  final Dio _dio = Dio(BaseOptions(baseUrl: serverBaseUrl));

  final Color _bg = const Color(0xFFF6F7F8);
  final Color _primary = const Color(0xFF137FEC);
  final Color _text = const Color(0xFF0F172A);
  final Color _muted = const Color(0xFF64748B);

  VocabPhase _phase = VocabPhase.setup;
  bool _loading = false;
  String _level = 'beginner';
  int _questionCount = 10;

  List<VocabSrsItem> _memorizationItems = <VocabSrsItem>[];
  List<VocabMcqItem> _quizItems = <VocabMcqItem>[];
  int _memorizationIndex = 0;
  int _quizIndex = 0;
  int _streak = 0;
  int _solved = 0;
  int _correct = 0;

  int? _mcqSelected;
  bool _showMcqResult = false;
  DateTime? _studyStartedAt;
  DateTime? _quizStartedAt;
  bool _studyRecordSaved = false;

  bool get _isQuizEntry => widget.entryMode == VocabEntryMode.quiz;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    final settings = await AppSettingsStore.instance.load();
    if (!mounted) return;
    setState(() => _level = settings.defaultDifficulty);
  }

  String _levelLabel(String level) {
    switch (level) {
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

  String _difficultyLabel(int difficulty) {
    if (difficulty <= 1) return '초급';
    if (difficulty == 2) return '중급';
    return '상급';
  }

  Future<void> _startMemorization() async {
    setState(() => _loading = true);
    try {
      final res = await _dio.get(
        '/vocab/srs/next',
        queryParameters: {'limit': _questionCount, 'level': _level},
      );
      final items = (res.data as List)
          .map(
            (e) => VocabSrsItem.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      setState(() {
        _memorizationItems = items;
        _quizItems = <VocabMcqItem>[];
        _memorizationIndex = 0;
        _quizIndex = 0;
        _streak = 0;
        _solved = 0;
        _correct = 0;
        _mcqSelected = null;
        _showMcqResult = false;
        _phase = items.isNotEmpty ? VocabPhase.memorizing : VocabPhase.setup;
        _studyStartedAt = items.isNotEmpty ? DateTime.now() : null;
        _studyRecordSaved = false;
      });
      if (items.isEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('학습할 단어를 불러오지 못했습니다.')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('학습 시작 중 오류가 발생했습니다.')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submitMcqGrade(bool isCorrect) async {
    if (_quizItems.isEmpty) return;
    final item = _quizItems[_quizIndex];
    try {
      await _dio.post(
        '/vocab/srs/review',
        data: <String, dynamic>{
          'card_id': item.cardId,
          'grade': isCorrect ? 'good' : 'again',
        },
      );
    } catch (_) {}
  }

  Future<void> _startQuiz() async {
    if (_memorizationItems.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await _dio.get(
        '/vocab/quiz/mcq/next',
        queryParameters: {
          'limit': _memorizationItems.length,
          'level': _level,
          'card_ids': _memorizationItems.map((e) => e.cardId).toList(),
        },
      );
      final items = (res.data as List)
          .map(
            (e) => VocabMcqItem.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      if (!mounted) return;
      if (items.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('시험 문제를 불러오지 못했습니다.')));
        return;
      }
      setState(() {
        _quizItems = items;
        _quizIndex = 0;
        _streak = 0;
        _solved = 0;
        _correct = 0;
        _mcqSelected = null;
        _showMcqResult = false;
        _phase = VocabPhase.quiz;
        _quizStartedAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('시험 시작 중 오류가 발생했습니다.')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _startDirectQuiz() async {
    setState(() => _loading = true);
    try {
      final res = await _dio.get(
        '/vocab/quiz/mcq/next',
        queryParameters: {'limit': _questionCount, 'level': _level},
      );
      final items = (res.data as List)
          .map(
            (e) => VocabMcqItem.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      if (!mounted) return;
      if (items.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('시험 문제를 불러오지 못했습니다.')));
        return;
      }
      setState(() {
        _memorizationItems = <VocabSrsItem>[];
        _quizItems = items;
        _quizIndex = 0;
        _streak = 0;
        _solved = 0;
        _correct = 0;
        _mcqSelected = null;
        _showMcqResult = false;
        _phase = VocabPhase.quiz;
        _quizStartedAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('시험 시작 중 오류가 발생했습니다.')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _resetToSetup() {
    setState(() {
      _phase = VocabPhase.setup;
      _memorizationItems = <VocabSrsItem>[];
      _quizItems = <VocabMcqItem>[];
      _memorizationIndex = 0;
      _quizIndex = 0;
      _streak = 0;
      _solved = 0;
      _correct = 0;
      _mcqSelected = null;
      _showMcqResult = false;
      _studyStartedAt = null;
      _quizStartedAt = null;
      _studyRecordSaved = false;
    });
  }

  Future<void> _goNextQuiz() async {
    final total = _quizItems.length;
    if (_quizIndex + 1 >= total) {
      final solved = _solved;
      final correct = _correct;
      final quizStartedAt = _quizStartedAt;
      if (quizStartedAt != null) {
        await LearningActivityRecorder.recordVocabQuiz(
          durationSec: DateTime.now().difference(quizStartedAt).inSeconds,
          level: _level,
          questionCount: solved,
          correctCount: correct,
          fromStudyFlow: !_isQuizEntry,
        );
      }
      if (!mounted) return;
      _resetToSetup();
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('시험 완료'),
          content: Text('정답 $correct / $solved'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() {
      _quizIndex += 1;
      _mcqSelected = null;
      _showMcqResult = false;
    });
  }

  void _checkMcqAnswer() {
    if (_quizItems.isEmpty || _mcqSelected == null) return;
    final item = _quizItems[_quizIndex];
    final ok = _mcqSelected == item.answerIndex;
    setState(() {
      _showMcqResult = true;
      _solved += 1;
      if (ok) {
        _correct += 1;
        _streak += 1;
      } else {
        _streak = 0;
      }
    });
    _submitMcqGrade(ok);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: _buildCurrentView()),
    );
  }

  Widget _buildCurrentView() {
    switch (_phase) {
      case VocabPhase.setup:
        return _buildSetupView();
      case VocabPhase.memorizing:
        return _buildMemorizationView();
      case VocabPhase.readyForQuiz:
        return _buildReadyForQuizView();
      case VocabPhase.quiz:
        return _buildQuizView();
    }
  }

  Widget _buildSetupView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          _isQuizEntry ? '단어 시험 설정' : '단어 학습 설정',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: _text,
          ),
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('난이도 선택'),
        const SizedBox(height: 10),
        Row(
          children: [
            _levelTile('beginner'),
            const SizedBox(width: 10),
            _levelTile('intermediate'),
            const SizedBox(width: 10),
            _levelTile('advanced'),
          ],
        ),
        const SizedBox(height: 24),
        _buildSectionTitle('문항 수: $_questionCount'),
        Slider(
          value: _questionCount.toDouble(),
          min: 5,
          max: 20,
          divisions: 15,
          activeColor: _primary,
          onChanged: (v) => setState(() => _questionCount = v.round()),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            _isQuizEntry
                ? '선택한 설정\n난이도: ${_levelLabel(_level)}\n객관식 문제로 바로 시험 시작'
                : '선택한 설정\n난이도: ${_levelLabel(_level)}\n암기 후 같은 단어로 객관식 시험',
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: _loading
                ? null
                : (_isQuizEntry ? _startDirectQuiz : _startMemorization),
            child: _loading
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(
                    _isQuizEntry ? '시험 시작' : '암기 시작',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: _muted,
        fontWeight: FontWeight.w800,
        fontSize: 15,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _levelTile(String level) {
    final selected = _level == level;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _level = level),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: selected ? _primary.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _primary : const Color(0xFFE2E8F0),
              width: selected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              _levelLabel(level),
              style: TextStyle(
                color: selected ? _primary : _text,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhaseHeader({
    required int current,
    required int total,
    required String title,
    required VoidCallback onBack,
  }) {
    final progress = total == 0 ? 0.0 : current / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, size: 28),
              ),
              Expanded(
                child: Text(
                  '$title · $current / $total',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.local_fire_department, color: _primary),
                  const SizedBox(width: 4),
                  Text(
                    '$_streak',
                    style: TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress,
              color: _primary,
              backgroundColor: const Color(0xFFD8DEE9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemorizationView() {
    if (_memorizationItems.isEmpty) {
      return const Center(child: Text('학습할 카드가 없습니다.'));
    }
    final item = _memorizationItems[_memorizationIndex];
    final isLast = _memorizationIndex == _memorizationItems.length - 1;
    return Column(
      children: [
        _buildPhaseHeader(
          current: _memorizationIndex + 1,
          total: _memorizationItems.length,
          title: '암기',
          onBack: _resetToSetup,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            children: [
              Text(
                '카드를 보고 단어를 암기하세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _difficultyLabel(item.difficulty),
                        style: TextStyle(
                          color: _primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      item.lemma,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _text,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      item.meaningKo,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _primary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if ((item.exampleEn ?? '').isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          item.exampleEn!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _muted,
                            fontWeight: FontWeight.w600,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        side: const BorderSide(
                          color: Color(0xFFD7DFEB),
                          width: 2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _memorizationIndex == 0
                          ? null
                          : () => setState(() => _memorizationIndex -= 1),
                      child: const Text('이전'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: _primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        if (isLast) {
                          final studyStartedAt = _studyStartedAt;
                          if (studyStartedAt != null && !_studyRecordSaved) {
                            LearningActivityRecorder.recordVocabStudy(
                              durationSec: DateTime.now()
                                  .difference(studyStartedAt)
                                  .inSeconds,
                              level: _level,
                              wordCount: _memorizationItems.length,
                            );
                            _studyRecordSaved = true;
                          }
                          setState(() => _phase = VocabPhase.readyForQuiz);
                          return;
                        }
                        setState(() => _memorizationIndex += 1);
                      },
                      child: Text(isLast ? '암기 완료' : '다음'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReadyForQuizView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 40),
        Icon(Icons.check_circle, size: 72, color: _primary),
        const SizedBox(height: 20),
        Text(
          '암기가 완료되었습니다',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _text,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${_memorizationItems.length}개의 단어를 암기했습니다.\n같은 단어들로 바로 시험을 볼 수 있습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            height: 1.5,
            color: _muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            '난이도: ${_levelLabel(_level)}\n시험 형식: 객관식\n출제 범위: 방금 암기한 단어만',
            style: TextStyle(
              color: _muted,
              fontWeight: FontWeight.w700,
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: _primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          onPressed: _loading ? null : _startQuiz,
          child: _loading
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text(
                  '시험 시작',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            side: const BorderSide(color: Color(0xFFD7DFEB), width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          onPressed: _resetToSetup,
          child: const Text('처음으로'),
        ),
      ],
    );
  }

  Widget _buildQuizView() {
    if (_quizItems.isEmpty) {
      return const Center(child: Text('학습할 카드가 없습니다.'));
    }
    final item = _quizItems[_quizIndex];
    return Column(
      children: [
        _buildPhaseHeader(
          current: _quizIndex + 1,
          total: _quizItems.length,
          title: '시험',
          onBack: _resetToSetup,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            children: [
              Text(
                item.direction == 'word_to_meaning'
                    ? '올바른 뜻을 선택하세요'
                    : '올바른 단어를 선택하세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                item.questionText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 58,
                  fontWeight: FontWeight.w800,
                  color: _text,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 28),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: item.choices.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.2,
                ),
                itemBuilder: (_, i) {
                  final isAnswer = i == item.answerIndex;
                  final isSelected = i == _mcqSelected;
                  Color bg = Colors.white;
                  Color border = const Color(0xFFD8E1EC);
                  if (_showMcqResult && isAnswer) {
                    bg = const Color(0xFFEAF8EF);
                    border = const Color(0xFF22C55E);
                  } else if (_showMcqResult && isSelected && !isAnswer) {
                    bg = const Color(0xFFFFEFEF);
                    border = const Color(0xFFEF4444);
                  } else if (isSelected) {
                    bg = _primary.withValues(alpha: 0.12);
                    border = _primary;
                  }
                  return InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: _showMcqResult
                        ? null
                        : () => setState(() => _mcqSelected = i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: border, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            item.choices[i],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _text,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              if (!_showMcqResult)
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: _primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _mcqSelected == null ? null : _checkMcqAnswer,
                  child: const Text('채점'),
                ),
              if (_showMcqResult)
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: _primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _goNextQuiz,
                  child: Text(
                    _quizIndex + 1 >= _quizItems.length ? '결과 보기' : '다음',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
