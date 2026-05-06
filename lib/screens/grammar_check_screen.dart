import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/statistics/learning_activity_recorder.dart';
import 'theme.dart';

/// AI 문법 검사 화면
class GrammarCheckScreen extends StatefulWidget {
  const GrammarCheckScreen({super.key});

  @override
  State<GrammarCheckScreen> createState() => _GrammarCheckScreenState();
}

class _GrammarCheckScreenState extends State<GrammarCheckScreen> {
  final TextEditingController _textController = TextEditingController();
  bool _isChecking = false;
  bool _hasResult = false;
  DateTime? _sessionStartedAt;

  // 예시 결과 데이터
  String _correctedSentence = '';
  List<GrammarError> _errors = [];

  @override
  void initState() {
    super.initState();
    _sessionStartedAt = DateTime.now();
    // 예시 문장 초기화
    _textController.text = 'He go to school yesterday.';
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _checkGrammar() {
    if (_textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('문장을 입력해주세요')));
      return;
    }

    setState(() {
      _isChecking = true;
    });

    // 시뮬레이션: 실제로는 API 호출
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _hasResult = true;
        _correctedSentence = 'He went to school yesterday.';
        _errors = [
          GrammarError(
            original: 'go',
            corrected: 'went',
            sentence: 'He go to school yesterday.',
            explanation:
                '시제 불일치: 어제(yesterday)는 과거 시점이므로 동사 \'go\'는 과거형인 \'went\'로 사용해야 합니다.',
          ),
        ];
      });
      final startedAt = _sessionStartedAt;
      if (startedAt != null) {
        LearningActivityRecorder.recordGrammarCheck(
          durationSec: DateTime.now().difference(startedAt).inSeconds,
          errorCount: _errors.length,
          suggestionCount: _errors.length,
        );
        _sessionStartedAt = DateTime.now();
      }
    });
  }

  void _clearText() {
    setState(() {
      _textController.clear();
      _hasResult = false;
    });
    _sessionStartedAt = DateTime.now();
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('클립보드에 복사되었습니다')));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.backgroundDark
          : AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF18232E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'AI 문법 검사',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              // 히스토리 기능 (향후 구현)
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 입력 필드
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '영어 문장을 입력하세요',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppTheme.textLight : AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF18232E) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF364657)
                          : const Color(0xFFDBE0E6),
                    ),
                  ),
                  child: Stack(
                    children: [
                      TextField(
                        controller: _textController,
                        maxLines: 6,
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark
                              ? AppTheme.textLight
                              : AppTheme.textDark,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.only(
                            left: 16,
                            right: 48,
                            top: 16,
                            bottom: 16,
                          ),
                          hintText: '예: I am goes to school.',
                          hintStyle: TextStyle(
                            color: isDark
                                ? AppTheme.textSecondary.withValues(alpha: 0.6)
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      if (_textController.text.isNotEmpty)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: IconButton(
                            icon: Icon(
                              Icons.cancel,
                              color: isDark
                                  ? AppTheme.textSecondary
                                  : AppTheme.textSecondary,
                              size: 20,
                            ),
                            onPressed: _clearText,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 검사 버튼
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isChecking ? null : _checkGrammar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isChecking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        '검사하기',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),

            // 결과 섹션
            if (_hasResult) ...[
              const SizedBox(height: 32),

              Text(
                '검사 결과',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.textLight : AppTheme.textDark,
                ),
              ),

              const SizedBox(height: 12),

              // 수정된 문장 카드
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF18232E) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF364657)
                        : const Color(0xFFDBE0E6),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '수정된 문장',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _correctedSentence,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppTheme.textLight
                                  : AppTheme.textDark,
                              height: 1.4,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.content_copy,
                            size: 20,
                            color: AppTheme.textSecondary,
                          ),
                          onPressed: () => _copyToClipboard(_correctedSentence),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 오류 상세 카드
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF18232E) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF364657)
                        : const Color(0xFFDBE0E6),
                  ),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _errors.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    thickness: 1,
                    color: isDark
                        ? const Color(0xFF364657)
                        : const Color(0xFFDBE0E6),
                    indent: 16,
                    endIndent: 16,
                  ),
                  itemBuilder: (context, index) {
                    final error = _errors[index];
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark
                                    ? AppTheme.textLight
                                    : AppTheme.textDark,
                              ),
                              children: [
                                TextSpan(
                                  text: error.sentence.replaceAll(
                                    error.original,
                                    '',
                                  ),
                                ),
                                TextSpan(
                                  text: error.original,
                                  style: const TextStyle(
                                    decoration: TextDecoration.lineThrough,
                                    color: Color(0xFFFF6B6B),
                                  ),
                                ),
                                const TextSpan(text: ' '),
                                TextSpan(
                                  text: error.corrected,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF4CAF50),
                                  ),
                                ),
                                TextSpan(
                                  text: error.sentence
                                      .split(error.original)
                                      .last,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.backgroundDark
                                  : AppTheme.backgroundLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.school,
                                  size: 18,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    error.explanation,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// 문법 오류 모델
class GrammarError {
  final String original;
  final String corrected;
  final String sentence;
  final String explanation;

  GrammarError({
    required this.original,
    required this.corrected,
    required this.sentence,
    required this.explanation,
  });
}
