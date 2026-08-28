import 'package:androidircx/core/sound/sound_service.dart';
import 'package:audioplayers/audioplayers.dart';

/// Production [SoundPlayer] backed by the `audioplayers` plugin. A single
/// player instance is reused; a new event sound cuts off the previous one.
class AudioplayersSoundPlayer implements SoundPlayer {
  AudioplayersSoundPlayer() {
    _player.setReleaseMode(ReleaseMode.stop);
  }

  final AudioPlayer _player = AudioPlayer(playerId: 'event-sounds');

  @override
  Future<void> play(String assetPath, double volume) async {
    await _player.stop();
    await _player.play(AssetSource(assetPath), volume: volume);
  }
}
