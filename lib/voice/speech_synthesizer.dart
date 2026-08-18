import '../core/result.dart';

/// Provider-neutral speech output used by the application response layer.
abstract interface class SpeechSynthesizer {
  Future<Result<void>> initialize();

  /// Completes when playback finishes, is interrupted, or fails.
  Future<Result<void>> speak(String text);

  Future<void> stop();

  Future<void> dispose();
}
