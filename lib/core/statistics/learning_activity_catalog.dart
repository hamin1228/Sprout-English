import 'package:flutter/material.dart';

import '../../screens/theme.dart';
import 'learning_activity_record.dart';

class LearningDomainSpec {
  const LearningDomainSpec({
    required this.domain,
    required this.title,
    required this.icon,
    required this.color,
  });

  final String domain;
  final String title;
  final IconData icon;
  final Color color;
}

class LearningFeatureSpec {
  const LearningFeatureSpec({
    required this.featureId,
    required this.title,
    required this.domain,
    required this.icon,
    required this.color,
    required this.emptyMessage,
  });

  final String featureId;
  final String title;
  final String domain;
  final IconData icon;
  final Color color;
  final String emptyMessage;
}

class LearningActivityCatalog {
  static const domainSpecs = [
    LearningDomainSpec(
      domain: LearningDomains.speaking,
      title: 'Speaking',
      icon: Icons.record_voice_over,
      color: Color(0xFF137FEC),
    ),
    LearningDomainSpec(
      domain: LearningDomains.writing,
      title: 'Writing',
      icon: Icons.edit_note,
      color: Color(0xFF22C55E),
    ),
    LearningDomainSpec(
      domain: LearningDomains.vocabulary,
      title: 'Vocabulary',
      icon: Icons.translate,
      color: Color(0xFF0EA5E9),
    ),
    LearningDomainSpec(
      domain: LearningDomains.rolePlaying,
      title: 'Role-playing',
      icon: Icons.groups,
      color: Color(0xFFF59E0B),
    ),
  ];

  static const featureSpecs = [
    LearningFeatureSpec(
      featureId: LearningFeatureIds.aiTutorChat,
      title: 'AI 튜터 채팅',
      domain: LearningDomains.speaking,
      icon: Icons.chat_bubble_outline,
      color: Color(0xFF3B82F6),
      emptyMessage: '첫 대화를 시작하면 메시지 수와 대화 세션 통계가 여기에 쌓입니다.',
    ),
    LearningFeatureSpec(
      featureId: LearningFeatureIds.aiFreeTalk,
      title: 'AI 프리토킹',
      domain: LearningDomains.speaking,
      icon: Icons.record_voice_over,
      color: AppTheme.success,
      emptyMessage: '프리토킹을 채점하면 총점과 세부 항목 평균이 여기에 표시됩니다.',
    ),
    LearningFeatureSpec(
      featureId: LearningFeatureIds.vocabStudy,
      title: '단어 학습',
      domain: LearningDomains.vocabulary,
      icon: Icons.translate,
      color: Color(0xFF0EA5E9),
      emptyMessage: '암기 세트를 완료하면 학습한 단어 수와 복습 기록이 누적됩니다.',
    ),
    LearningFeatureSpec(
      featureId: LearningFeatureIds.vocabQuiz,
      title: '단어 시험',
      domain: LearningDomains.vocabulary,
      icon: Icons.quiz_outlined,
      color: Color(0xFF2563EB),
      emptyMessage: '단어 시험을 풀면 정답률과 문제 수 통계가 여기에 표시됩니다.',
    ),
    LearningFeatureSpec(
      featureId: LearningFeatureIds.roleplay,
      title: '롤플레잉',
      domain: LearningDomains.rolePlaying,
      icon: Icons.groups,
      color: Color(0xFFF59E0B),
      emptyMessage: '롤플레잉을 시작하면 시나리오별 진행 기록과 완료율이 쌓입니다.',
    ),
    LearningFeatureSpec(
      featureId: LearningFeatureIds.toeicWriting,
      title: 'TOEIC Writing',
      domain: LearningDomains.writing,
      icon: Icons.auto_stories_outlined,
      color: Color(0xFF22C55E),
      emptyMessage: 'TOEIC Writing를 제출하면 유형별 점수와 응시 기록이 쌓입니다.',
    ),
    LearningFeatureSpec(
      featureId: LearningFeatureIds.grammarCheck,
      title: 'AI 문법 검사',
      domain: LearningDomains.writing,
      icon: Icons.check_circle,
      color: Color(0xFF137FEC),
      emptyMessage: '문법 검사를 실행하면 오류 수와 수정 제안 통계가 여기에 표시됩니다.',
    ),
    LearningFeatureSpec(
      featureId: LearningFeatureIds.toneConversion,
      title: '문장 톤 변환',
      domain: LearningDomains.writing,
      icon: Icons.swap_horiz_rounded,
      color: Color(0xFF4A90E2),
      emptyMessage: '톤 변환을 실행하면 사용한 톤 분포와 변환 횟수가 누적됩니다.',
    ),
  ];

  static LearningFeatureSpec featureById(String featureId) {
    for (final spec in featureSpecs) {
      if (spec.featureId == featureId) {
        return spec;
      }
    }

    return LearningFeatureSpec(
      featureId: featureId,
      title: featureId,
      domain: LearningDomains.speaking,
      icon: Icons.insights,
      color: AppTheme.primary,
      emptyMessage: '아직 기록이 없습니다.',
    );
  }

  static LearningDomainSpec domainById(String domain) {
    for (final spec in domainSpecs) {
      if (spec.domain == domain) {
        return spec;
      }
    }

    return const LearningDomainSpec(
      domain: LearningDomains.speaking,
      title: 'Speaking',
      icon: Icons.record_voice_over,
      color: AppTheme.primary,
    );
  }
}
