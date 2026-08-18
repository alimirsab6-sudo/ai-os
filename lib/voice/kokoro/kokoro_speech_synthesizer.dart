import '../../core/events/app_event.dart';
import '../../core/events/event_bus.dart';
import '../../core/result.dart';
import '../audio/speech_audio_player.dart';
import '../speech_synthesizer.dart';
import 'kokoro_bridge.dart';

final class KokoroSpeechSynthesizer implements SpeechSynthesizer {
  KokoroSpeechSynthesizer({
    required this.bridge,
    required this.audioPlayer,
    required this.events,
    void Function(String message)? diagnostics,
  }) : diagnostics = diagnostics ?? _noDiagnostics;

  final KokoroBridge bridge;
  final SpeechAudioPlayer audioPlayer;
  final EventPublisher events;
  final void Function(String message) diagnostics;

  static void _noDiagnostics(String _) {}

  int _nextRequestId = 0;
  int _activeGeneration = 0;
  bool _initialized = false;
  bool _disposed = false;
  bool _playing = false;
  Future<Result<void>>? _initialization;

  @override
  Future<Result<void>> initialize() {
    if (_disposed) {
      return Future.value(
        const Result.failure(
          Failure('Speech is unavailable.', code: 'speech_disposed'),
        ),
      );
    }
    if (_initialized) return Future.value(const Result.success(null));
    final current = _initialization;
    if (current != null) return current;
    return _initialization = _initializeBridge();
  }

  Future<Result<void>> _initializeBridge() async {
    final result = await bridge.initialize();
    return result.fold(
      (_) {
        _initialized = true;
        _publish('tts.runtime.ready');
        return const Result.success(null);
      },
      (failure) {
        _initialization = null;
        _publish('tts.failed', {
          'stage': 'initialize',
          'failure_code': failure.code,
        });
        return Result.failure(failure);
      },
    );
  }

  @override
  Future<Result<void>> speak(String text) async {
    final requestCreatedAtEpochMicroseconds =
        DateTime.now().microsecondsSinceEpoch;
    final normalized = text.trim();
    if (normalized.isEmpty ||
        normalized.length > KokoroBridgeRequest.maxTextLength) {
      return const Result.failure(
        Failure('Speech text is invalid.', code: 'invalid_speech_text'),
      );
    }
    if (_disposed) {
      return const Result.failure(
        Failure('Speech is unavailable.', code: 'speech_disposed'),
      );
    }

    final generation = ++_activeGeneration;
    final request = KokoroBridgeRequest(
      id: (++_nextRequestId).toString(),
      text: normalized,
      createdAtEpochMicroseconds: requestCreatedAtEpochMicroseconds,
    );
    _publish('tts.request.created', {'request_id': request.id});
    if (_playing) {
      await audioPlayer.stop();
      _playing = false;
    }

    final initialized = await initialize();
    if (initialized case Failed<void>(:final failure)) {
      return Result.failure(failure);
    }
    if (_isInterrupted(generation)) return _stoppedResult();

    _publish('tts.generation.started', {'request_id': request.id});
    final generated = await bridge.synthesize(request);
    if (_isInterrupted(generation)) return _stoppedResult();
    if (generated case Failed<KokoroAudioArtifact>(:final failure)) {
      _publish('tts.failed', {
        'stage': 'generation',
        'request_id': request.id,
        'failure_code': failure.code,
      });
      return Result.failure(failure);
    }

    final artifact = (generated as Success<KokoroAudioArtifact>).value;
    final playerReceivedAtEpochMicroseconds =
        DateTime.now().microsecondsSinceEpoch;
    final flutterToPlayerMilliseconds =
        artifact.flutterReceivedAtEpochMicroseconds == 0
        ? 0
        : (playerReceivedAtEpochMicroseconds -
                  artifact.flutterReceivedAtEpochMicroseconds) /
              1000;
    diagnostics(
      '[TTS:${request.id}] T6->T7 flutter_to_player '
      '${flutterToPlayerMilliseconds.toStringAsFixed(1)} ms',
    );
    _publish('tts.audio.generated', {
      'request_id': request.id,
      'audio_path': artifact.filePath,
      'file_size': artifact.fileSize,
      'format_tag': artifact.formatTag,
      'sample_rate': artifact.sampleRate,
      'channels': artifact.channels,
      'bits_per_sample': artifact.bitsPerSample,
      'non_zero_samples': artifact.nonZeroSampleCount,
      'cache_hit': artifact.cacheHit,
    });
    final playback = await audioPlayer.play(
      artifact.filePath,
      onStarted: () {
        if (_isInterrupted(generation)) return;
        _playing = true;
        _publish('tts.playback.started', {
          'request_id': request.id,
          'sample_rate': artifact.sampleRate,
          'channels': artifact.channels,
        });
      },
    );
    _playing = false;
    if (_isInterrupted(generation)) return _stoppedResult();
    return playback.fold(
      (_) {
        _publish('tts.playback.completed', {'request_id': request.id});
        return const Result.success(null);
      },
      (failure) {
        _publish('tts.failed', {
          'stage': 'playback',
          'request_id': request.id,
          'failure_code': failure.code,
        });
        return Result.failure(failure);
      },
    );
  }

  bool _isInterrupted(int generation) =>
      _disposed || generation != _activeGeneration;

  Result<void> _stoppedResult() => const Result.failure(
    Failure('Speech was stopped.', code: 'speech_stopped'),
  );

  @override
  Future<void> stop() async {
    _activeGeneration++;
    final wasPlaying = _playing;
    _playing = false;
    await audioPlayer.stop();
    if (wasPlaying) _publish('tts.playback.stopped');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await audioPlayer.dispose();
    await bridge.dispose();
    _publish('tts.disposed');
  }

  void _publish(String type, [Map<String, Object?> data = const {}]) {
    events.publish(
      ApplicationEvent(
        type: type,
        occurredAt: DateTime.now().toUtc(),
        data: data,
      ),
    );
  }
}
