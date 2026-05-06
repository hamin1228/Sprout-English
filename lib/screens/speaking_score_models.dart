import 'package:flutter/material.dart';

class SpeakingScoreResult {
  const SpeakingScoreResult({
    required this.version,
    required this.taskId,
    required this.scores,
    required this.totalScore,
    required this.overallSummary,
    required this.nextActions,
    required this.confidence,
    this.appliedTotalScoreCap,
  });

  final String version;
  final String taskId;
  final Map<String, SpeakingDimensionScore> scores;
  final int totalScore;
  final String overallSummary;
  final List<String> nextActions;
  final double confidence;
  final int? appliedTotalScoreCap;

  static const List<String> orderedKeys = [
    'task_fulfillment_interaction',
    'pronunciation_delivery',
    'fluency',
    'grammar_control',
    'vocabulary_expression',
  ];

  factory SpeakingScoreResult.fromJson(Map<String, dynamic> json) {
    final rawScores = Map<String, dynamic>.from(
      (json['scores'] as Map?) ?? const <String, dynamic>{},
    );

    final scores = <String, SpeakingDimensionScore>{};
    for (final key in orderedKeys) {
      scores[key] = SpeakingDimensionScore.fromJson(
        key,
        Map<String, dynamic>.from(
          (rawScores[key] as Map?) ?? const <String, dynamic>{},
        ),
      );
    }

    final diagnostics = Map<String, dynamic>.from(
      (json['diagnostics'] as Map?) ?? const <String, dynamic>{},
    );

    return SpeakingScoreResult(
      version: (json['version'] ?? 'speaking_rubric_v1').toString(),
      taskId: (json['task_id'] ?? 'free_talk').toString(),
      scores: scores,
      totalScore: _asInt(json['total_score']),
      overallSummary: (json['overall_summary'] ?? '').toString(),
      nextActions: ((json['next_actions'] as List?) ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .take(2)
          .toList(),
      confidence: _asDouble(diagnostics['confidence']).clamp(0.0, 1.0),
      appliedTotalScoreCap: diagnostics['applied_total_score_cap'] == null
          ? null
          : _asInt(diagnostics['applied_total_score_cap']),
    );
  }

  factory SpeakingScoreResult.demo() {
    return SpeakingScoreResult(
      version: 'speaking_rubric_v1',
      taskId: 'roleplay_restaurant_001',
      scores: {
        'task_fulfillment_interaction': const SpeakingDimensionScore(
          key: 'task_fulfillment_interaction',
          level: 4,
          score: 26,
          evidence: '예약 요청과 핵심 정보 전달은 적절했고 후속 질문에도 반응했습니다.',
          feedback: '대답은 충분히 자연스러웠고, 한두 문장만 더 확장하면 상호작용 점수가 더 올라갑니다.',
        ),
        'pronunciation_delivery': const SpeakingDimensionScore(
          key: 'pronunciation_delivery',
          level: 3,
          score: 14,
          evidence: '전달은 대체로 이해 가능했지만 발음 명료도는 아주 안정적이지는 않았습니다.',
          feedback: '핵심 문장을 조금 더 또렷하게 끊어 말하면 전달력이 좋아집니다.',
        ),
        'fluency': const SpeakingDimensionScore(
          key: 'fluency',
          level: 3,
          score: 14,
          evidence: '대화는 이어졌지만 중간중간 멈춤이 보여 흐름이 약간 끊겼습니다.',
          feedback: '짧은 연결 표현을 미리 익혀 두면 멈춤을 줄이는 데 도움이 됩니다.',
        ),
        'grammar_control': const SpeakingDimensionScore(
          key: 'grammar_control',
          level: 4,
          score: 13,
          evidence: '기본 문장 구조는 안정적이었고 의미 전달도 명확했습니다.',
          feedback: '기본 문장은 좋습니다. 같은 패턴을 조금만 더 다양하게 써보세요.',
        ),
        'vocabulary_expression': const SpeakingDimensionScore(
          key: 'vocabulary_expression',
          level: 3,
          score: 11,
          evidence: '과제에는 맞는 어휘를 사용했지만 표현 폭은 제한적이었습니다.',
          feedback: '같은 의미를 다른 표현으로 바꿔 말하는 연습을 하면 점수가 더 좋아집니다.',
        ),
      },
      totalScore: 78,
      overallSummary: '핵심 요구는 잘 수행했고, 발화 흐름과 표현 확장을 조금만 더 다듬으면 전체 완성도가 높아집니다.',
      nextActions: const [
        '짧은 연결 표현을 묶어서 반복 연습해 멈춤을 줄여보세요.',
        '같은 뜻을 다른 단어와 문장으로 바꿔 말하는 연습을 추가해보세요.',
      ],
      confidence: 0.82,
    );
  }

  List<SpeakingDimensionScore> get orderedScores =>
      orderedKeys.map((key) => scores[key]!).toList();

  String get gradeLabel {
    if (totalScore >= 90) return 'Excellent';
    if (totalScore >= 80) return 'Very Good';
    if (totalScore >= 70) return 'Good';
    if (totalScore >= 60) return 'Fair';
    return 'Needs Work';
  }

  Color get gradeColor {
    if (totalScore >= 80) return const Color(0xFF28A745);
    if (totalScore >= 60) return const Color(0xFFFFC107);
    return const Color(0xFFE15241);
  }
}

class SpeakingDimensionScore {
  const SpeakingDimensionScore({
    required this.key,
    required this.level,
    required this.score,
    required this.evidence,
    required this.feedback,
  });

  final String key;
  final int level;
  final int score;
  final String evidence;
  final String feedback;

  factory SpeakingDimensionScore.fromJson(
    String key,
    Map<String, dynamic> json,
  ) {
    return SpeakingDimensionScore(
      key: key,
      level: _asInt(json['level']).clamp(0, 5),
      score: _asInt(json['score']).clamp(0, 30),
      evidence: (json['evidence'] ?? '').toString(),
      feedback: (json['feedback'] ?? '').toString(),
    );
  }

  String get title {
    switch (key) {
      case 'task_fulfillment_interaction':
        return '과업 수행 및 상호작용';
      case 'pronunciation_delivery':
        return '발음 및 전달 명료도';
      case 'fluency':
        return '유창성';
      case 'grammar_control':
        return '문법 정확성';
      case 'vocabulary_expression':
        return '어휘 및 표현 범위';
      default:
        return key;
    }
  }

  String get subtitle {
    switch (key) {
      case 'task_fulfillment_interaction':
        return 'Task Fulfillment & Interaction';
      case 'pronunciation_delivery':
        return 'Pronunciation & Delivery';
      case 'fluency':
        return 'Fluency';
      case 'grammar_control':
        return 'Grammar Control';
      case 'vocabulary_expression':
        return 'Vocabulary & Expressive Range';
      default:
        return key;
    }
  }

  IconData get icon {
    switch (key) {
      case 'task_fulfillment_interaction':
        return Icons.forum;
      case 'pronunciation_delivery':
        return Icons.graphic_eq;
      case 'fluency':
        return Icons.speed;
      case 'grammar_control':
        return Icons.rule;
      case 'vocabulary_expression':
        return Icons.menu_book;
      default:
        return Icons.assessment;
    }
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
