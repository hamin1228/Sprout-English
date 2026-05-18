import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

abstract class RoleplayTtsPlayer {
  Future<void> play(Uint8List bytes);
  Future<void> stop();
  Future<void> dispose();
}

class JustAudioRoleplayTtsPlayer implements RoleplayTtsPlayer {
  JustAudioRoleplayTtsPlayer({AudioPlayer? player}) : _player = player;

  AudioPlayer? _player;

  AudioPlayer _ensurePlayer() {
    return _player ??= AudioPlayer();
  }

  @override
  Future<void> play(Uint8List bytes) async {
    final player = _ensurePlayer();
    await player.stop();
    await player.setAudioSource(_MemoryAudioSource(bytes));
    await player.play();
  }

  @override
  Future<void> stop() async {
    final player = _player;
    if (player == null) return;
    await player.stop();
    await player.dispose();
    _player = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}

// ignore: experimental_member_use
class _MemoryAudioSource extends StreamAudioSource {
  _MemoryAudioSource(this.bytes);

  final Uint8List bytes;

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final safeStart = start ?? 0;
    final safeEnd = end ?? bytes.length;
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: safeEnd - safeStart,
      offset: safeStart,
      stream: Stream<List<int>>.value(bytes.sublist(safeStart, safeEnd)),
      contentType: 'audio/wav',
    );
  }
}
