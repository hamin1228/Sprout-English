import 'package:flutter/material.dart';

import '../../screens/grammar_check_screen.dart';
import '../../screens/theme.dart';
import '../../screens/tone_conversion_screen.dart';
import 'toeic_writing_page.dart';

class WritingHubPage extends StatelessWidget {
  const WritingHubPage({super.key});

  void _openPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundLight,
        elevation: 0,
        title: const Text(
          'Writing Hub',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _FeatureCard(
            icon: Icons.auto_stories_outlined,
            color: const Color(0xFF22C55E),
            title: 'TOEIC Writing 연습',
            subtitle: '사진, 이메일, 의견 에세이 유형을 단계별로 훈련합니다.',
            onTap: () => _openPage(context, const ToeicWritingPage()),
          ),
          const SizedBox(height: 12),
          _FeatureCard(
            icon: Icons.rule_folder_outlined,
            color: const Color(0xFF137FEC),
            title: 'AI 문법 검사',
            subtitle: '문장 오류를 빠르게 찾고 수정 제안을 확인합니다.',
            onTap: () => _openPage(context, const GrammarCheckScreen()),
          ),
          const SizedBox(height: 12),
          _FeatureCard(
            icon: Icons.swap_horiz_rounded,
            color: const Color(0xFF0EA5E9),
            title: '문장 톤 변환',
            subtitle: '같은 메시지를 더 격식 있게 혹은 간결하게 바꿉니다.',
            onTap: () => _openPage(context, const ToneConversionScreen()),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
