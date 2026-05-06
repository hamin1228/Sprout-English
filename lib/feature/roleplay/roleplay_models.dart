class RoleplayStageSummary {
  final String id;
  final String title;
  final String objectiveKo;
  final String hintEn;

  const RoleplayStageSummary({
    required this.id,
    required this.title,
    required this.objectiveKo,
    required this.hintEn,
  });

  factory RoleplayStageSummary.fromJson(Map<String, dynamic> json) {
    return RoleplayStageSummary(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      objectiveKo: (json['objective_ko'] ?? '').toString(),
      hintEn: (json['hint_en'] ?? '').toString(),
    );
  }
}

class RoleplayCatalogItemModel {
  final String id;
  final String difficulty;
  final String title;
  final String subtitle;
  final String summaryKo;
  final int estimatedMinutes;
  final String backgroundAsset;
  final String aiRole;
  final String userGoalKo;
  final String openingLine;
  final List<RoleplayStageSummary> stages;

  const RoleplayCatalogItemModel({
    required this.id,
    required this.difficulty,
    required this.title,
    required this.subtitle,
    required this.summaryKo,
    required this.estimatedMinutes,
    required this.backgroundAsset,
    required this.aiRole,
    required this.userGoalKo,
    required this.openingLine,
    required this.stages,
  });

  factory RoleplayCatalogItemModel.fromJson(Map<String, dynamic> json) {
    final rawStages = (json['stages'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(RoleplayStageSummary.fromJson)
        .toList();
    return RoleplayCatalogItemModel(
      id: (json['id'] ?? '').toString(),
      difficulty: (json['difficulty'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      summaryKo: (json['summary_ko'] ?? '').toString(),
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt() ?? 4,
      backgroundAsset: (json['background_asset'] ?? '').toString(),
      aiRole: (json['ai_role'] ?? '').toString(),
      userGoalKo: (json['user_goal_ko'] ?? '').toString(),
      openingLine: (json['opening_line'] ?? '').toString(),
      stages: rawStages,
    );
  }
}

class RoleplaySessionStateModel {
  final String state;
  final int turnIndex;
  final String? scenarioId;
  final String? difficulty;
  final int stageIndex;
  final String stageStatus;
  final List<String> completedObjectives;
  final int redirectCount;
  final bool isComplete;
  final int? estimatedMinutes;

  const RoleplaySessionStateModel({
    required this.state,
    required this.turnIndex,
    required this.scenarioId,
    required this.difficulty,
    required this.stageIndex,
    required this.stageStatus,
    required this.completedObjectives,
    required this.redirectCount,
    required this.isComplete,
    required this.estimatedMinutes,
  });

  factory RoleplaySessionStateModel.fromJson(Map<String, dynamic> json) {
    return RoleplaySessionStateModel(
      state: (json['state'] ?? 'INIT').toString(),
      turnIndex: (json['turn_index'] as num?)?.toInt() ?? 0,
      scenarioId: json['scenario_id']?.toString(),
      difficulty: json['difficulty']?.toString(),
      stageIndex: (json['stage_index'] as num?)?.toInt() ?? 0,
      stageStatus: (json['stage_status'] ?? 'idle').toString(),
      completedObjectives:
          (json['completed_objectives'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      redirectCount: (json['redirect_count'] as num?)?.toInt() ?? 0,
      isComplete: json['is_complete'] == true,
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt(),
    );
  }
}

class RoleplayGenerateResult {
  final String sessionId;
  final int turnIndex;
  final String assistantUtterance;
  final String? currentStageTitle;
  final String? currentObjectiveKo;
  final String? hintEn;
  final bool shouldRedirect;
  final bool sessionComplete;
  final String? ttsText;
  final RoleplaySessionStateModel state;
  final Map<String, dynamic> meta;

  const RoleplayGenerateResult({
    required this.sessionId,
    required this.turnIndex,
    required this.assistantUtterance,
    required this.currentStageTitle,
    required this.currentObjectiveKo,
    required this.hintEn,
    required this.shouldRedirect,
    required this.sessionComplete,
    required this.ttsText,
    required this.state,
    required this.meta,
  });

  factory RoleplayGenerateResult.fromJson(Map<String, dynamic> json) {
    return RoleplayGenerateResult(
      sessionId: (json['session_id'] ?? '').toString(),
      turnIndex: (json['turn_index'] as num?)?.toInt() ?? 0,
      assistantUtterance: (json['assistant_utterance'] ?? '').toString(),
      currentStageTitle: json['current_stage_title']?.toString(),
      currentObjectiveKo: json['current_objective_ko']?.toString(),
      hintEn: json['hint_en']?.toString(),
      shouldRedirect: json['should_redirect'] == true,
      sessionComplete: json['session_complete'] == true,
      ttsText: json['tts_text']?.toString(),
      state: RoleplaySessionStateModel.fromJson(
        Map<String, dynamic>.from(
          json['state'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      meta: Map<String, dynamic>.from(
        json['meta'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }
}

class RoleplayChatMessage {
  final bool isUser;
  final String text;
  final bool isRedirect;

  const RoleplayChatMessage({
    required this.isUser,
    required this.text,
    this.isRedirect = false,
  });
}
