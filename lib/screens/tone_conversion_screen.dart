import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/statistics/learning_activity_recorder.dart';
import 'theme.dart';

/// 문장 톤 변환 화면
class ToneConversionScreen extends StatefulWidget {
  const ToneConversionScreen({super.key});

  @override
  State<ToneConversionScreen> createState() => _ToneConversionScreenState();
}

class _ToneConversionScreenState extends State<ToneConversionScreen> {
  final TextEditingController _textController = TextEditingController();

  // 선택된 톤
  ToneType? _selectedTone;

  // 변환 상태
  bool _isConverting = false;
  bool _hasResult = false;

  // 결과 문장
  String _convertedSentence = '';

  DateTime? _sessionStartedAt;

  @override
  void initState() {
    super.initState();
    _sessionStartedAt = DateTime.now();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _selectTone(ToneType tone) {
    setState(() {
      _selectedTone = tone;
    });
  }

  void _convertTone() {
    if (_textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('문장을 입력해주세요')));
      return;
    }

    if (_selectedTone == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('톤을 선택해주세요')));
      return;
    }

    setState(() {
      _isConverting = true;
    });

    // 시뮬레이션: 실제로는 API 호출
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _isConverting = false;
        _hasResult = true;

        // 톤별 예시 결과
        switch (_selectedTone!) {
          case ToneType.formal:
            _convertedSentence =
                'I would be most grateful if you could provide assistance with this matter at your earliest convenience.';
            break;
          case ToneType.polite:
            _convertedSentence =
                'Would you mind helping me with this when you have a moment?';
            break;
          case ToneType.friendly:
            _convertedSentence =
                'Hey! Could you help me out with this when you get a chance?';
            break;
          case ToneType.concise:
            _convertedSentence = 'Please help when possible.';
            break;
        }
      });
      final startedAt = _sessionStartedAt;
      final selectedTone = _selectedTone;
      if (startedAt != null && selectedTone != null) {
        LearningActivityRecorder.recordToneConversion(
          durationSec: DateTime.now().difference(startedAt).inSeconds,
          tone: selectedTone.name,
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

  void _playTTS() {
    // TTS 기능 (향후 구현)
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('TTS 기능은 준비 중입니다')));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const primaryColor = Color(0xFF4A90E2);
    const accentColor = Color(0xFF50E3C2);

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.backgroundDark
          : const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: isDark
            ? const Color(0xFF1D2833).withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.8),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '문장 톤 변환',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16).copyWith(bottom: 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Original Sentence 섹션
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Original Sentence',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppTheme.textLight
                            : const Color(0xFF1D1D1F),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1D2833) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF3A444D)
                              : const Color(0xFFE5E5E7),
                        ),
                      ),
                      child: Stack(
                        children: [
                          TextField(
                            controller: _textController,
                            maxLines: 5,
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark
                                  ? AppTheme.textLight
                                  : const Color(0xFF1D1D1F),
                            ),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.only(
                                left: 16,
                                right: 48,
                                top: 16,
                                bottom: 16,
                              ),
                              hintText: 'Enter your sentence here...',
                              hintStyle: TextStyle(
                                color: isDark
                                    ? AppTheme.textLight.withValues(alpha: 0.5)
                                    : const Color(
                                        0xFF1D1D1F,
                                      ).withValues(alpha: 0.5),
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
                                      ? AppTheme.textLight.withValues(
                                          alpha: 0.6,
                                        )
                                      : const Color(
                                          0xFF1D1D1F,
                                        ).withValues(alpha: 0.6),
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

                const SizedBox(height: 24),

                // Choose a Tone 섹션
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose a Tone',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppTheme.textLight
                            : const Color(0xFF1D1D1F),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 2.5,
                      children: [
                        _ToneButton(
                          type: ToneType.formal,
                          label: 'Formal',
                          subtitle: '보고서, 비즈니스 이메일',
                          isSelected: _selectedTone == ToneType.formal,
                          isDark: isDark,
                          onTap: () => _selectTone(ToneType.formal),
                        ),
                        _ToneButton(
                          type: ToneType.polite,
                          label: 'Polite',
                          subtitle: '정중한 요청, 고객 문의',
                          isSelected: _selectedTone == ToneType.polite,
                          isDark: isDark,
                          onTap: () => _selectTone(ToneType.polite),
                        ),
                        _ToneButton(
                          type: ToneType.friendly,
                          label: 'Friendly',
                          subtitle: '친구와의 대화',
                          isSelected: _selectedTone == ToneType.friendly,
                          isDark: isDark,
                          onTap: () => _selectTone(ToneType.friendly),
                        ),
                        _ToneButton(
                          type: ToneType.concise,
                          label: 'Concise',
                          subtitle: '핵심 요약, 제목',
                          isSelected: _selectedTone == ToneType.concise,
                          isDark: isDark,
                          onTap: () => _selectTone(ToneType.concise),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // AI Generated Result 섹션
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Generated Result',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppTheme.textLight
                            : const Color(0xFF1D1D1F),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 로딩 또는 결과 표시
                    if (_isConverting)
                      Container(
                        height: 160,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1D2833)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF3A444D)
                                : const Color(0xFFE5E5E7),
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    primaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Generating...',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? AppTheme.textLight.withValues(
                                          alpha: 0.7,
                                        )
                                      : const Color(
                                          0xFF1D1D1F,
                                        ).withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_hasResult)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? primaryColor.withValues(alpha: 0.2)
                              : primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${_selectedTone!.label} Tone',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? accentColor : primaryColor,
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.volume_up,
                                        size: 20,
                                        color: isDark
                                            ? accentColor.withValues(alpha: 0.8)
                                            : primaryColor,
                                      ),
                                      onPressed: _playTTS,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(
                                        Icons.content_copy,
                                        size: 20,
                                        color: isDark
                                            ? accentColor.withValues(alpha: 0.8)
                                            : primaryColor,
                                      ),
                                      onPressed: () =>
                                          _copyToClipboard(_convertedSentence),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _convertedSentence,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.5,
                                color: isDark
                                    ? AppTheme.textLight
                                    : const Color(0xFF1D1D1F),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        height: 160,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1D2833)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF3A444D)
                                : const Color(0xFFE5E5E7),
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '문장과 톤을 선택한 후\nAI로 변환하기 버튼을 눌러주세요',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? AppTheme.textLight.withValues(alpha: 0.5)
                                  : const Color(
                                      0xFF1D1D1F,
                                    ).withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // 하단 고정 버튼
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          AppTheme.backgroundDark.withValues(alpha: 0),
                          AppTheme.backgroundDark,
                        ]
                      : [
                          const Color(0xFFF5F5F7).withValues(alpha: 0),
                          const Color(0xFFF5F5F7),
                        ],
                ),
              ),
              child: ElevatedButton(
                onPressed: _isConverting ? null : _convertTone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 8,
                  shadowColor: primaryColor.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size(double.infinity, 56),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.auto_awesome),
                    SizedBox(width: 8),
                    Text(
                      'AI로 변환하기',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 톤 버튼 위젯
class _ToneButton extends StatelessWidget {
  final ToneType type;
  final String label;
  final String subtitle;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _ToneButton({
    required this.type,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF4A90E2);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor
              : (isDark ? const Color(0xFF1D2833) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? primaryColor
                : (isDark ? const Color(0xFF3A444D) : const Color(0xFFE5E5E7)),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark ? AppTheme.textLight : const Color(0xFF1D1D1F)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.8)
                    : (isDark
                          ? AppTheme.textLight.withValues(alpha: 0.6)
                          : const Color(0xFF1D1D1F).withValues(alpha: 0.6)),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// 톤 타입 열거형
enum ToneType {
  formal('Formal'),
  polite('Polite'),
  friendly('Friendly'),
  concise('Concise');

  final String label;
  const ToneType(this.label);
}
