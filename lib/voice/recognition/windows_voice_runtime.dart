import 'dart:typed_data';
import '../../core/result.dart';
import 'local_voice_runtime.dart';

final class WindowsVoiceRuntime implements LocalVoiceRuntime {
  bool _initialized = false;

  WindowsVoiceRuntime({
    required this.paths,
  });

  final VoiceRuntimePaths paths;

  @override
  Future<Result<void>> initialize() async {
    _initialized = true;
    return const Result.success(null);
  }

  @override
  Future<Result<String>> transcribe(Float32List samples) async {
    if (!_initialized) {
      return Result.failure(
        const Failure(
          'Voice runtime has not been initialized.',
          code: 'runtime_not_initialized',
        ),
      );
    }

    return Result.failure(
      const Failure(
        'Windows speech recognition backend is not configured yet.',
        code: 'stt_backend_unavailable',
      ),
    );
  }

  @override
  Future<Result<Float32List>> createSpeakerEmbedding(
    Float32List samples,
  ) async {
    if (!_initialized) {
      return Result.failure(
        const Failure(
          'Voice runtime has not been initialized.',
          code: 'runtime_not_initialized',
        ),
      );
    }

    return Result.failure(
      const Failure(
        'Speaker embedding backend is not configured yet.',
        code: 'speaker_backend_unavailable',
      ),
    );
  }

  @override
  Future<Result<bool>> detectWakePhrase(Float32List samples) async {
    if (!_initialized) {
      return Result.failure(
        const Failure(
          'Voice runtime has not been initialized.',
          code: 'runtime_not_initialized',
        ),
      );
    }

    return const Result.success(false);
  }

  @override
  Future<Result<void>> resetWakePhrase() async {
    return const Result.success(null);
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }
}
