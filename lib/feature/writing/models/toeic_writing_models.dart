import 'package:flutter/material.dart';

enum ToeicWritingTaskType { picture, email, opinion }

extension ToeicWritingTaskTypeX on ToeicWritingTaskType {
  String get apiValue => switch (this) {
    ToeicWritingTaskType.picture => 'picture',
    ToeicWritingTaskType.email => 'email',
    ToeicWritingTaskType.opinion => 'opinion',
  };

  String get label => switch (this) {
    ToeicWritingTaskType.picture => '사진 묘사',
    ToeicWritingTaskType.email => '이메일 응답',
    ToeicWritingTaskType.opinion => '의견 에세이',
  };

  String get subtitle => switch (this) {
    ToeicWritingTaskType.picture => '문항 1-5 스타일 문장 훈련',
    ToeicWritingTaskType.email => '문항 6-7 스타일 답장 작성',
    ToeicWritingTaskType.opinion => '문항 8 스타일 의견 전개',
  };

  IconData get icon => switch (this) {
    ToeicWritingTaskType.picture => Icons.image_outlined,
    ToeicWritingTaskType.email => Icons.mail_outline,
    ToeicWritingTaskType.opinion => Icons.lightbulb_outline,
  };

  Color get accentColor => switch (this) {
    ToeicWritingTaskType.picture => const Color(0xFF137FEC),
    ToeicWritingTaskType.email => const Color(0xFF0EA5E9),
    ToeicWritingTaskType.opinion => const Color(0xFF22C55E),
  };
}

enum ToeicWritingLevel { beginner, intermediate, advanced }

extension ToeicWritingLevelX on ToeicWritingLevel {
  String get apiValue => switch (this) {
    ToeicWritingLevel.beginner => 'beginner',
    ToeicWritingLevel.intermediate => 'intermediate',
    ToeicWritingLevel.advanced => 'advanced',
  };

  String get label => switch (this) {
    ToeicWritingLevel.beginner => '초급',
    ToeicWritingLevel.intermediate => '중급',
    ToeicWritingLevel.advanced => '상급',
  };
}

String? _normalizeToeicImageAssetPath(String? path) {
  if (path == null) return null;
  if (path.contains('assets/toeic_writing_images/') && path.endsWith('.png')) {
    return '${path.substring(0, path.length - 4)}.jpg';
  }
  return path;
}

class ToeicWritingPrompt {
  ToeicWritingPrompt({
    required this.promptId,
    required this.taskType,
    required this.title,
    required this.instructions,
    required this.timeLimitSec,
    required this.recommendedWords,
    required this.requiredPoints,
    required this.imageAsset,
    required this.sourceText,
    required this.keywords,
    required this.modelAnswer,
  });

  final String promptId;
  final ToeicWritingTaskType taskType;
  final String title;
  final String instructions;
  final int timeLimitSec;
  final int recommendedWords;
  final List<String> requiredPoints;
  final String? imageAsset;
  final String? sourceText;
  final List<List<String>> keywords;
  final String modelAnswer;

  factory ToeicWritingPrompt.fromJson(Map<String, dynamic> json) {
    return ToeicWritingPrompt(
      promptId: json['prompt_id'] as String,
      taskType: ToeicWritingTaskType.values.firstWhere(
        (value) => value.apiValue == json['task_type'],
      ),
      title: json['title'] as String,
      instructions: json['instructions'] as String,
      timeLimitSec: json['time_limit_sec'] as int,
      recommendedWords: json['recommended_words'] as int,
      requiredPoints: (json['required_points'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      imageAsset: _normalizeToeicImageAssetPath(json['image_asset'] as String?),
      sourceText: json['source_text'] as String?,
      keywords: (json['keywords'] as List<dynamic>? ?? <dynamic>[])
          .map(
            (group) => (group as List<dynamic>)
                .map((item) => item.toString())
                .toList(),
          )
          .toList(),
      modelAnswer: (json['model_answer'] as String?) ?? '',
    );
  }
}

class ToeicRubricItem {
  ToeicRubricItem({
    required this.label,
    required this.score,
    required this.maxScore,
    required this.feedback,
  });

  final String label;
  final int score;
  final int maxScore;
  final String feedback;

  factory ToeicRubricItem.fromJson(Map<String, dynamic> json) {
    return ToeicRubricItem(
      label: json['label'] as String,
      score: json['score'] as int,
      maxScore: json['max_score'] as int,
      feedback: json['feedback'] as String,
    );
  }
}

class ToeicWritingEvaluation {
  ToeicWritingEvaluation({
    required this.overallScore,
    required this.rubric,
    required this.modelAnswer,
    required this.contentAnalysis,
    required this.grammarFeedback,
    required this.matchedPoints,
    required this.missingPoints,
    required this.betterAnswerTips,
    required this.recordId,
  });

  final int overallScore;
  final List<ToeicRubricItem> rubric;
  final String modelAnswer;
  final List<String> contentAnalysis;
  final List<String> grammarFeedback;
  final List<String> matchedPoints;
  final List<String> missingPoints;
  final List<String> betterAnswerTips;
  final int? recordId;

  factory ToeicWritingEvaluation.fromJson(Map<String, dynamic> json) {
    return ToeicWritingEvaluation(
      overallScore: json['overall_score'] as int,
      rubric: (json['rubric'] as List<dynamic>? ?? <dynamic>[])
          .map(
            (item) => ToeicRubricItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      modelAnswer: json['model_answer'] as String,
      contentAnalysis:
          (json['content_analysis'] as List<dynamic>? ?? <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      grammarFeedback:
          (json['grammar_feedback'] as List<dynamic>? ?? <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      matchedPoints: (json['matched_points'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      missingPoints: (json['missing_points'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      betterAnswerTips:
          (json['better_answer_tips'] as List<dynamic>? ?? <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      recordId: json['record_id'] as int?,
    );
  }
}
