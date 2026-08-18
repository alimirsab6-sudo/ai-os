import '../../core/result.dart';

/// Plays a trusted audio artifact created by the speech runtime.
abstract interface class SpeechAudioPlayer {
  Future<Result<void>> play(
    String filePath, {
    required void Function() onStarted,
  });

  Future<void> stop();

  Future<void> dispose();
}
