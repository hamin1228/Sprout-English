import 'dart:async';

import 'package:audio_session/audio_session.dart';

class ConversationAudioSession {
  static const Duration routeSettleDelay = Duration(milliseconds: 220);

  static const AudioSessionConfiguration _playbackConfiguration =
      AudioSessionConfiguration.speech();

  static const AudioSessionConfiguration _recordingConfiguration =
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions(0x4 | 0x8),
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientExclusive,
        androidWillPauseWhenDucked: true,
      );

  Future<void> prepareForPlayback() async {
    final session = await AudioSession.instance;
    await session.configure(_playbackConfiguration);
    await session.setActive(true);
  }

  Future<void> prepareForRecording() async {
    final session = await AudioSession.instance;
    await session.configure(_recordingConfiguration);
    await session.setActive(true);
    await Future<void>.delayed(routeSettleDelay);
  }

  Future<void> deactivate() async {
    final session = await AudioSession.instance;
    await session.setActive(false);
  }
}
