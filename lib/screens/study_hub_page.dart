import 'package:flutter/material.dart';

import '../feature/vocab/vocab_page.dart';
import '../feature/writing/toeic_writing_page.dart';
import 'ai_tutor_chat_screen_exact.dart';
import 'grammar_check_screen.dart';
import 'push_to_talk_freetalk_screen_exact.dart';
import 'roleplay_settings_screen_exact.dart';
import 'theme.dart';
import 'tone_conversion_screen.dart';

class StudyHubPage extends StatelessWidget {
  const StudyHubPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  static final List<_StudySectionData> _sections = [
    _StudySectionData(
      title: 'Conversation / Speaking',
      items: [
        _StudyItemData(
          icon: Icons.chat_bubble_outline,
          title: 'AI 튜터 채팅',
          subtitle: '실시간 메시지 대화로 영어 표현과 답변 흐름을 연습합니다.',
          color: const Color(0xFF3B82F6),
          screen: const AiTutorChatScreenExact(),
        ),
        _StudyItemData(
          icon: Icons.record_voice_over,
          title: 'AI 프리토킹',
          subtitle: '버튼을 누르며 자유롭게 말하고 AI와 자연스럽게 대화를 이어갑니다.',
          color: AppTheme.success,
          screen: const PushToTalkFreeTalkScreenExact(),
        ),
      ],
    ),
    _StudySectionData(
      title: 'Vocabulary',
      items: [
        _StudyItemData(
          icon: Icons.translate,
          title: '단어 학습',
          subtitle: '새 단어를 익히고 뜻과 예문을 보며 암기 단계를 진행합니다.',
          color: const Color(0xFF0EA5E9),
          screen: const VocabPage(),
        ),
        _StudyItemData(
          icon: Icons.quiz_outlined,
          title: '단어 시험',
          subtitle: '객관식 문제로 어휘 실력을 바로 점검하고 정답률을 확인합니다.',
          color: const Color(0xFF2563EB),
          screen: const VocabPage(entryMode: VocabEntryMode.quiz),
        ),
      ],
    ),
    _StudySectionData(
      title: 'Role-playing',
      items: [
        _StudyItemData(
          icon: Icons.settings,
          title: '롤플레잉',
          subtitle: '상황과 난이도를 고른 뒤 실제 대화처럼 역할 연습을 시작합니다.',
          color: const Color(0xFFF59E0B),
          screen: const RolePlaySettingsScreenExact(),
        ),
      ],
    ),
    _StudySectionData(
      title: 'Writing',
      items: [
        _StudyItemData(
          icon: Icons.auto_stories_outlined,
          title: 'TOEIC Writing',
          subtitle: '사진, 이메일, 에세이 유형으로 토익 라이팅 실전을 연습합니다.',
          color: const Color(0xFF22C55E),
          screen: const ToeicWritingPage(),
        ),
        _StudyItemData(
          icon: Icons.check_circle,
          title: 'AI 문법 검사',
          subtitle: '영어 문장의 오류를 찾고 더 자연스러운 표현으로 고칩니다.',
          color: const Color(0xFF137FEC),
          screen: const GrammarCheckScreen(),
        ),
        _StudyItemData(
          icon: Icons.swap_horiz_rounded,
          title: '문장 톤 변환',
          subtitle: '같은 문장을 격식, 친근함, 간결함에 맞게 다시 표현합니다.',
          color: const Color(0xFF4A90E2),
          screen: const ToneConversionScreen(),
        ),
      ],
    ),
  ];

  void _openPage(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final listView = ListView(
      padding: EdgeInsets.fromLTRB(16, showAppBar ? 8 : 20, 16, 24),
      children: [
        if (!showAppBar) ...[
          const Text(
            'Study',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 20),
        ],
        for (final section in _sections) ...[
          Text(
            section.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 12),
          for (final item in section.items) ...[
            _StudyFeatureCard(
              item: item,
              onTap: () => _openPage(context, item.screen),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 16),
        ],
      ],
    );

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: showAppBar
          ? AppBar(
              backgroundColor: AppTheme.backgroundLight,
              elevation: 0,
              title: const Text(
                'Study',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            )
          : null,
      body: listView,
    );
  }
}

class _StudySectionData {
  const _StudySectionData({required this.title, required this.items});

  final String title;
  final List<_StudyItemData> items;
}

class _StudyItemData {
  const _StudyItemData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.screen,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget screen;
}

class _StudyFeatureCard extends StatelessWidget {
  const _StudyFeatureCard({required this.item, required this.onTap});

  final _StudyItemData item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: item.color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400], size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
