class AppSettingsStorageKeys {
  static const reminderEnabled = 'reminder_enabled';
  static const reminderTime = 'reminder_time';
  static const streakReminderEnabled = 'streak_reminder_enabled';
  static const defaultDifficulty = 'default_difficulty';
  static const roleplaySubtitleDefault = 'roleplay_subtitle_default';
  static const explanationLanguage = 'explanation_language';
  static const aiVoiceAutoplay = 'ai_voice_autoplay';
  static const silenceAutoStop = 'silence_auto_stop';
  static const serverBaseUrl = 'server_base_url';
}

class AppSettings {
  const AppSettings({
    this.reminderEnabled = false,
    this.reminderTime = '20:00',
    this.streakReminderEnabled = false,
    this.defaultDifficulty = 'beginner',
    this.roleplaySubtitleDefault = false,
    this.explanationLanguage = 'korean',
    this.aiVoiceAutoplay = true,
    this.silenceAutoStop = true,
    this.serverBaseUrl = '',
  });

  final bool reminderEnabled;
  final String reminderTime;
  final bool streakReminderEnabled;
  final String defaultDifficulty;
  final bool roleplaySubtitleDefault;
  final String explanationLanguage;
  final bool aiVoiceAutoplay;
  final bool silenceAutoStop;
  final String serverBaseUrl;

  AppSettings copyWith({
    bool? reminderEnabled,
    String? reminderTime,
    bool? streakReminderEnabled,
    String? defaultDifficulty,
    bool? roleplaySubtitleDefault,
    String? explanationLanguage,
    bool? aiVoiceAutoplay,
    bool? silenceAutoStop,
    String? serverBaseUrl,
  }) {
    return AppSettings(
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderTime: reminderTime ?? this.reminderTime,
      streakReminderEnabled:
          streakReminderEnabled ?? this.streakReminderEnabled,
      defaultDifficulty: _normalizeDifficulty(
        defaultDifficulty ?? this.defaultDifficulty,
      ),
      roleplaySubtitleDefault:
          roleplaySubtitleDefault ?? this.roleplaySubtitleDefault,
      explanationLanguage: _normalizeLanguage(
        explanationLanguage ?? this.explanationLanguage,
      ),
      aiVoiceAutoplay: aiVoiceAutoplay ?? this.aiVoiceAutoplay,
      silenceAutoStop: silenceAutoStop ?? this.silenceAutoStop,
      serverBaseUrl: serverBaseUrl ?? this.serverBaseUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      AppSettingsStorageKeys.reminderEnabled: reminderEnabled,
      AppSettingsStorageKeys.reminderTime: reminderTime,
      AppSettingsStorageKeys.streakReminderEnabled: streakReminderEnabled,
      AppSettingsStorageKeys.defaultDifficulty: defaultDifficulty,
      AppSettingsStorageKeys.roleplaySubtitleDefault: roleplaySubtitleDefault,
      AppSettingsStorageKeys.explanationLanguage: explanationLanguage,
      AppSettingsStorageKeys.aiVoiceAutoplay: aiVoiceAutoplay,
      AppSettingsStorageKeys.silenceAutoStop: silenceAutoStop,
      AppSettingsStorageKeys.serverBaseUrl: serverBaseUrl,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      reminderEnabled:
          json[AppSettingsStorageKeys.reminderEnabled] as bool? ?? false,
      reminderTime:
          json[AppSettingsStorageKeys.reminderTime] as String? ?? '20:00',
      streakReminderEnabled:
          json[AppSettingsStorageKeys.streakReminderEnabled] as bool? ?? false,
      defaultDifficulty: _normalizeDifficulty(
        json[AppSettingsStorageKeys.defaultDifficulty] as String? ?? 'beginner',
      ),
      roleplaySubtitleDefault:
          json[AppSettingsStorageKeys.roleplaySubtitleDefault] as bool? ??
          false,
      explanationLanguage: _normalizeLanguage(
        json[AppSettingsStorageKeys.explanationLanguage] as String? ?? 'korean',
      ),
      aiVoiceAutoplay:
          json[AppSettingsStorageKeys.aiVoiceAutoplay] as bool? ?? true,
      silenceAutoStop:
          json[AppSettingsStorageKeys.silenceAutoStop] as bool? ?? true,
      serverBaseUrl:
          json[AppSettingsStorageKeys.serverBaseUrl] as String? ?? '',
    );
  }

  static String _normalizeDifficulty(String value) {
    switch (value) {
      case 'beginner':
      case 'intermediate':
      case 'advanced':
        return value;
      default:
        return 'beginner';
    }
  }

  static String _normalizeLanguage(String value) {
    switch (value) {
      case 'korean':
      case 'english':
        return value;
      default:
        return 'korean';
    }
  }
}
