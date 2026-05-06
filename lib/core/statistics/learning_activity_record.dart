class LearningFeatureIds {
  static const aiTutorChat = 'ai_tutor_chat';
  static const aiFreeTalk = 'ai_free_talk';
  static const vocabStudy = 'vocab_study';
  static const vocabQuiz = 'vocab_quiz';
  static const roleplay = 'roleplay';
  static const toeicWriting = 'toeic_writing';
  static const grammarCheck = 'grammar_check';
  static const toneConversion = 'tone_conversion';

  static const ordered = [
    aiTutorChat,
    aiFreeTalk,
    vocabStudy,
    vocabQuiz,
    roleplay,
    toeicWriting,
    grammarCheck,
    toneConversion,
  ];
}

class LearningDomains {
  static const speaking = 'speaking';
  static const writing = 'writing';
  static const vocabulary = 'vocabulary';
  static const rolePlaying = 'role_playing';

  static const ordered = [speaking, writing, vocabulary, rolePlaying];
}

class LearningActivityRecord {
  const LearningActivityRecord({
    required this.featureId,
    required this.domain,
    required this.completedAt,
    required this.durationSec,
    this.score,
    this.scoreMax,
    this.attemptCount,
    this.correctCount,
    this.metadata = const <String, dynamic>{},
  });

  final String featureId;
  final String domain;
  final DateTime completedAt;
  final int durationSec;
  final int? score;
  final int? scoreMax;
  final int? attemptCount;
  final int? correctCount;
  final Map<String, dynamic> metadata;

  factory LearningActivityRecord.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'];
    return LearningActivityRecord(
      featureId: (json['featureId'] ?? '').toString(),
      domain: (json['domain'] ?? '').toString(),
      completedAt:
          DateTime.tryParse((json['completedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      durationSec: _asInt(json['durationSec']),
      score: json['score'] == null ? null : _asInt(json['score']),
      scoreMax: json['scoreMax'] == null ? null : _asInt(json['scoreMax']),
      attemptCount: json['attemptCount'] == null
          ? null
          : _asInt(json['attemptCount']),
      correctCount: json['correctCount'] == null
          ? null
          : _asInt(json['correctCount']),
      metadata: metadata is Map<String, dynamic>
          ? metadata
          : metadata is Map
          ? Map<String, dynamic>.from(metadata)
          : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'featureId': featureId,
      'domain': domain,
      'completedAt': completedAt.toIso8601String(),
      'durationSec': durationSec,
      'score': score,
      'scoreMax': scoreMax,
      'attemptCount': attemptCount,
      'correctCount': correctCount,
      'metadata': metadata,
    };
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
