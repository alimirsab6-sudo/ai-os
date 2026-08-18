import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

import '../../core/result.dart';
import 'speech_audio_player.dart';

/// Windows playback adapter. Completion comes from the media backend rather
/// than an estimated duration.
final class WindowsSpeechAudioPlayer implements SpeechAudioPlayer {
  WindowsSpeechAudioPlayer({
    AudioPlayer? player,
    void Function(String message)? diagnostics,
  }) : _player = player ?? AudioPlayer(),
       _diagnostics = diagnostics ?? _noDiagnostics {
    _completionSubscription = _player.onPlayerComplete.listen((_) {
      final elapsed = _playbackStopwatch?.elapsedMilliseconds ?? 0;
      final playbackMilliseconds = elapsed - _playbackStartedAtMilliseconds;
      _diagnostics(
        '[TTS] T8->T9 playback '
        '${playbackMilliseconds < 0 ? 0 : playbackMilliseconds} ms',
      );
      final completion = _activeCompletion;
      if (completion != null && !completion.isCompleted) {
        completion.complete(const Result.success(null));
      }
      _activeCompletion = null;
    }, onError: _handlePlaybackError);
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      _diagnostics('player_state=${state.name}');
      if (state == PlayerState.playing && !_started) {
        _started = true;
        _playbackStartedAtMilliseconds =
            _playbackStopwatch?.elapsedMilliseconds ?? 0;
        _diagnostics(
          '[TTS] T7->T8 player_prepare '
          '$_playbackStartedAtMilliseconds ms',
        );
        _onStarted?.call();
      }
    }, onError: _handlePlaybackError);
    _eventErrorSubscription = _player.eventStream.listen(
      (_) {},
      onError: _handlePlaybackError,
    );
  }

  final AudioPlayer _player;
  final void Function(String message) _diagnostics;
  late final StreamSubscription<void> _completionSubscription;
  late final StreamSubscription<PlayerState> _stateSubscription;
  late final StreamSubscription<AudioEvent> _eventErrorSubscription;
  Completer<Result<void>>? _activeCompletion;
  void Function()? _onStarted;
  bool _started = false;
  bool _disposed = false;
  Stopwatch? _playbackStopwatch;
  int _playbackStartedAtMilliseconds = 0;

  static void _noDiagnostics(String _) {}

  @override
  Future<Result<void>> play(
    String filePath, {
    required void Function() onStarted,
  }) async {
    if (_disposed) {
      return const Result.failure(
        Failure('Audio playback is unavailable.', code: 'audio_disposed'),
      );
    }
    await stop();
    final file = File(filePath);
    if (!file.existsSync()) {
      _diagnostics('audio_file_missing path=$filePath');
      return const Result.failure(
        Failure('Speech audio file is missing.', code: 'audio_file_missing'),
      );
    }
    final fileSize = file.lengthSync();
    if (fileSize <= 44) {
      _diagnostics('audio_file_empty path=$filePath bytes=$fileSize');
      return const Result.failure(
        Failure('Speech audio file is empty.', code: 'audio_file_empty'),
      );
    }
    _diagnostics('audio_file_ready path=$filePath bytes=$fileSize');
    final completion = Completer<Result<void>>();
    _activeCompletion = completion;
    _onStarted = onStarted;
    _started = false;
    _playbackStartedAtMilliseconds = 0;
    _playbackStopwatch = Stopwatch()..start();
    try {
      _diagnostics('playback_initializing');
      await _player.play(DeviceFileSource(filePath));
      _diagnostics('playback_initialized');
      return await completion.future;
    } catch (error) {
      _diagnostics('playback_error error=$error');
      if (!completion.isCompleted) {
        completion.complete(
          const Result.failure(
            Failure('Speech audio could not be played.', code: 'audio_failed'),
          ),
        );
      }
      _activeCompletion = null;
      _onStarted = null;
      return completion.future;
    }
  }

  @override
  Future<void> stop() async {
    final completion = _activeCompletion;
    _activeCompletion = null;
    _onStarted = null;
    _started = false;
    _playbackStopwatch = null;
    _playbackStartedAtMilliseconds = 0;
    if (completion != null && !completion.isCompleted) {
      completion.complete(
        const Result.failure(
          Failure('Speech playback was stopped.', code: 'speech_stopped'),
        ),
      );
    }
    if (!_disposed) await _player.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _completionSubscription.cancel();
    await _stateSubscription.cancel();
    await _eventErrorSubscription.cancel();
    await _player.dispose();
  }

  void _handlePlaybackError(Object error, [StackTrace? stackTrace]) {
    _diagnostics('playback_stream_error error=$error');
    final completion = _activeCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete(
        const Result.failure(
          Failure('Speech audio playback failed.', code: 'audio_failed'),
        ),
      );
    }
    _activeCompletion = null;
    _onStarted = null;
    _started = false;
    _playbackStopwatch = null;
    _playbackStartedAtMilliseconds = 0;
  }
}
