import '../../feature/writing/models/toeic_writing_models.dart';
import '../../screens/roleplay_scenarios_exact.dart';
import '../../screens/speaking_score_models.dart';
import 'learning_activity_record.dart';
import 'learning_activity_store.dart';

class LearningActivityRecorder {
  LearningActivityRecorder._();

  static Future<void> recordAiTutorChat({
    required int durationSec,
    required int turnCount,
  }) async {
    if (turnCount <= 0) return;
    await _addRecord(
      LearningActivityRecord(
        featureId: LearningFeatureIds.aiTutorChat,
        domain: LearningDomains.speaking,
        completedAt: DateTime.now(),
        durationSec: durationSec.clamp(0, 86400),
        metadata: <String, dynamic>{'turnCount': turnCount},
      ),
    );
  }

  static Future<void> recordFreeTalk({
    required int durationSec,
    required int userTurnCount,
    required SpeakingScoreResult result,
  }) async {
    await _addRecord(
      LearningActivityRecord(
        featureId: LearningFeatureIds.aiFreeTalk,
        domain: LearningDomains.speaking,
        completedAt: DateTime.now(),
        durationSec: durationSec.clamp(0, 86400),
        score: result.totalScore,
        scoreMax: 100,
        attemptCount: userTurnCount,
        metadata: <String, dynamic>{
          'gradeLabel': result.gradeLabel,
          'turnCount': userTurnCount,
          'dimensionScores': <String, dynamic>{
            for (final entry in result.scores.entries)
              entry.key: <String, dynamic>{
                'score': entry.value.score,
                'max': _speakingDimensionMax(entry.key),
              },
          },
        },
      ),
    );
  }

  static Future<void> recordVocabStudy({
    required int durationSec,
    required String level,
    required int wordCount,
  }) async {
    if (wordCount <= 0) return;
    await _addRecord(
      LearningActivityRecord(
        featureId: LearningFeatureIds.vocabStudy,
        domain: LearningDomains.vocabulary,
        completedAt: DateTime.now(),
        durationSec: durationSec.clamp(0, 86400),
        attemptCount: wordCount,
        metadata: <String, dynamic>{'level': level, 'wordCount': wordCount},
      ),
    );
  }

  static Future<void> recordVocabQuiz({
    required int durationSec,
    required String level,
    required int questionCount,
    required int correctCount,
    required bool fromStudyFlow,
  }) async {
    if (questionCount <= 0) return;
    await _addRecord(
      LearningActivityRecord(
        featureId: LearningFeatureIds.vocabQuiz,
        domain: LearningDomains.vocabulary,
        completedAt: DateTime.now(),
        durationSec: durationSec.clamp(0, 86400),
        attemptCount: questionCount,
        correctCount: correctCount.clamp(0, questionCount),
        metadata: <String, dynamic>{
          'level': level,
          'fromStudyFlow': fromStudyFlow,
        },
      ),
    );
  }

  static Future<void> recordRoleplay({
    required int durationSec,
    required RoleplayScenarioExact scenario,
    required bool completed,
    required int userTurnCount,
  }) async {
    await _addRecord(
      LearningActivityRecord(
        featureId: LearningFeatureIds.roleplay,
        domain: LearningDomains.rolePlaying,
        completedAt: DateTime.now(),
        durationSec: durationSec.clamp(0, 86400),
        attemptCount: userTurnCount,
        metadata: <String, dynamic>{
          'scenarioId': scenario.id,
          'scenarioTitle': scenario.title,
          'difficulty': scenario.difficulty,
          'completed': completed,
          'turnCount': userTurnCount,
        },
      ),
    );
  }

  static Future<void> recordToeicWriting({
    required int durationSec,
    required ToeicWritingTaskType taskType,
    required ToeicWritingLevel level,
    required ToeicWritingEvaluation evaluation,
  }) async {
    await _addRecord(
      LearningActivityRecord(
        featureId: LearningFeatureIds.toeicWriting,
        domain: LearningDomains.writing,
        completedAt: DateTime.now(),
        durationSec: durationSec.clamp(0, 86400),
        score: evaluation.overallScore,
        scoreMax: 100,
        metadata: <String, dynamic>{
          'taskType': taskType.apiValue,
          'taskTypeLabel': taskType.label,
          'level': level.apiValue,
          'levelLabel': level.label,
          'recordId': evaluation.recordId,
        },
      ),
    );
  }

  static Future<void> recordGrammarCheck({
    required int durationSec,
    required int errorCount,
    required int suggestionCount,
  }) async {
    await _addRecord(
      LearningActivityRecord(
        featureId: LearningFeatureIds.grammarCheck,
        domain: LearningDomains.writing,
        completedAt: DateTime.now(),
        durationSec: durationSec.clamp(0, 86400),
        metadata: <String, dynamic>{
          'errorCount': errorCount,
          'suggestionCount': suggestionCount,
        },
      ),
    );
  }

  static Future<void> recordToneConversion({
    required int durationSec,
    required String tone,
  }) async {
    await _addRecord(
      LearningActivityRecord(
        featureId: LearningFeatureIds.toneConversion,
        domain: LearningDomains.writing,
        completedAt: DateTime.now(),
        durationSec: durationSec.clamp(0, 86400),
        metadata: <String, dynamic>{'tone': tone},
      ),
    );
  }

  static Future<void> _addRecord(LearningActivityRecord record) {
    return LearningActivityStore.instance.add(record);
  }

  static int _speakingDimensionMax(String key) {
    switch (key) {
      case 'task_fulfillment_interaction':
        return 30;
      case 'pronunciation_delivery':
      case 'fluency':
        return 20;
      case 'grammar_control':
      case 'vocabulary_expression':
        return 15;
      default:
        return 20;
    }
  }
}
