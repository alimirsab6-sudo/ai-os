import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/events/app_event.dart';
import '../../core/events/event_bus.dart';
import '../../core/orchestrator/orchestrator.dart';
import '../../core/result.dart';
import '../input/microphone_capture.dart';
import '../profile/owner_profile_repository.dart';
import '../profile/owner_voice_profile.dart';
import '../recognition/local_voice_runtime.dart';
import '../speech_synthesizer.dart';
import 'voice_assistant.dart';

typedef VoiceCommandHandler =
    Future<Result<OrchestratorResponse>> Function(String transcript);

final class UnknownSpeakerSessionEvent {
  UnknownSpeakerSessionEvent({
    required this.id,
    required this.occurredAt,
    this.providedName,
    this.acknowledged = false,
  });

  final String id;
  final DateTime occurredAt;
  String? providedName;
  bool acknowledged;
}

final class LocalVoiceAssistant implements VoiceAssistant {
  LocalVoiceAssistant({
    required this.microphone,
    required this.runtime,
    required this.profiles,
    required this.speech,
    required this.events,
    required this.commandHandler,
    DateTime Function()? clock,
    Map<String, bool> Function()? foundationReadiness,
    void Function(String message)? diagnostics,
    this.lifecycleEvents,
  }) : clock = clock ?? DateTime.now,
       foundationReadiness = foundationReadiness ?? _noFoundationReadiness,
       diagnostics = diagnostics ?? _noDiagnostics;

  static const verificationThreshold = 0.75;
  static const _sampleRate = 16000;
  static const _wakeBufferSamples = _sampleRate * 4;
  static const _endOfSpeechSilenceSamples = _sampleRate * 3 ~/ 5;
  static const _wakeFallbackSilenceSamples = _sampleRate * 3 ~/ 5;

  final MicrophoneCapture microphone;
  final LocalVoiceRuntime runtime;
  final OwnerProfileRepository profiles;
  final SpeechSynthesizer speech;
  final EventPublisher events;
  final VoiceCommandHandler commandHandler;
  final DateTime Function() clock;
  final Map<String, bool> Function() foundationReadiness;
  final void Function(String message) diagnostics;
  final Stream<AppEvent>? lifecycleEvents;

  static Map<String, bool> _noFoundationReadiness() => const {};
  static void _noDiagnostics(String _) {}

  OwnerVoiceProfile? _profile;
  final List<UnknownSpeakerSessionEvent> _securityEvents = [];
  StreamSubscription<Float32List>? _wakeSubscription;
  final List<double> _wakeBuffer = [];
  Future<void> _wakeWork = Future.value();
  int _wakeSession = 0;
  int _wakeRecoveryAttempts = 0;
  int _wakeHealthySamples = 0;
  bool _wakeAudioObserved = false;
  bool _wakeSpeechObserved = false;
  bool _wakeKeywordDetected = false;
  int _wakeSilenceSamples = 0;
  int _wakeNoiseCalibrationSamples = 0;
  double _wakeNoiseFloor = 0.005;
  bool _wakeMonitoring = false;
  bool _handlingWake = false;
  bool _ownerVerified = false;
  bool _initialized = false;
  bool _disposed = false;
  bool _startupGreetingDelivered = false;
  Future<Result<void>>? _initialization;
  StreamSubscription<AppEvent>? _lifecycleSubscription;
  Future<void> _lifecycleWork = Future.value();
  bool _resumeWakeAfterSpeech = false;

  @override
  bool get hasOwnerProfile => _profile != null;

  @override
  bool get ownerVerified => _ownerVerified;

  @override
  bool get wakeMonitoring => _wakeMonitoring;

  @override
  Future<Result<void>> initialize() {
    if (_initialized) return Future.value(const Result.success(null));
    if (_disposed) {
      return Future.value(_failure('voice_disposed', 'Voice is unavailable.'));
    }
    final current = _initialization;
    if (current != null) return current;
    final task = _initialize();
    _initialization = task;
    unawaited(
      task.then((result) {
        if (result.isFailure) _initialization = null;
      }),
    );
    return task;
  }

  Future<Result<void>> _initialize() async {
    _lifecycleSubscription ??= lifecycleEvents?.listen(_onLifecycleEvent);
    _publish('voice.startup.started');
    final runtimeReady = await runtime.initialize();
    if (runtimeReady case Failed<void>(:final failure)) {
      _publishReadiness(
        runtimeReady: false,
        microphoneReady: false,
        profileReady: false,
        ttsReady: false,
      );
      return Result.failure(failure);
    }
    final ttsReady = await speech.initialize();
    if (ttsReady case Failed<void>(:final failure)) {
      _publishReadiness(
        runtimeReady: true,
        microphoneReady: false,
        profileReady: false,
        ttsReady: false,
      );
      return Result.failure(failure);
    }
    final loaded = await profiles.load();
    if (loaded case Failed<OwnerVoiceProfile?>(:final failure)) {
      _publishReadiness(
        runtimeReady: true,
        microphoneReady: false,
        profileReady: false,
      );
      return Result.failure(failure);
    }
    _profile = (loaded as Success<OwnerVoiceProfile?>).value;
    final microphoneCheck = await microphone.start();
    final microphoneReady = microphoneCheck.isSuccess;
    await microphone.stop();
    _initialized = true;
    _publishReadiness(
      runtimeReady: true,
      microphoneReady: microphoneReady,
      profileReady: _profile != null,
      ttsReady: true,
    );
    if (!microphoneReady) {
      return _failure(
        'microphone_failed',
        'Voice input is currently unavailable.',
      );
    }
    final profile = _profile;
    if (profile == null) {
      _publish('voice.enrollment.required');
      return const Result.success(null);
    }
    final greeting = await _deliverStartupGreeting(profile.displayName);
    if (greeting case Failed<void>(:final failure)) {
      return Result.failure(failure);
    }
    return startWakeMonitoring();
  }

  void _onLifecycleEvent(AppEvent event) {
    if (event.type == 'tts.playback.started' && _wakeMonitoring) {
      _resumeWakeAfterSpeech = true;
      _lifecycleWork = _lifecycleWork.then((_) => _stopWakeCapture());
      return;
    }
    if ((event.type == 'tts.playback.completed' ||
            event.type == 'tts.playback.stopped' ||
            event.type == 'tts.failed') &&
        _resumeWakeAfterSpeech) {
      _resumeWakeAfterSpeech = false;
      _lifecycleWork = _lifecycleWork.then((_) async {
        if (!_disposed && !_handlingWake && _profile != null) {
          await _restartWakeMonitoring();
        }
      });
    }
  }

  void _publishReadiness({
    required bool runtimeReady,
    required bool microphoneReady,
    required bool profileReady,
    bool ttsReady = true,
  }) {
    _publish('voice.startup.readiness', {
      ...foundationReadiness(),
      'stt': runtimeReady,
      'speaker_verification': runtimeReady,
      'wake_phrase': runtimeReady,
      'microphone': microphoneReady,
      'owner_profile': profileReady,
      'tts': ttsReady,
    });
  }

  Future<Result<void>> _deliverStartupGreeting(String name) async {
    if (_startupGreetingDelivered) return const Result.success(null);
    _startupGreetingDelivered = true;
    final greeting = _timeGreeting(clock().hour);
    _publish('voice.startup.greeting', {'display_name': name});
    final result = await speech.speak(
      '$greeting, $name. CronyX is online. Voice systems are ready.',
    );
    _publish('voice.startup.completed', {'audio_playback': result.isSuccess});
    return result;
  }

  static String _timeGreeting(int hour) {
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Future<Result<void>> enrollOwner(String displayName) async {
    final normalized = displayName.trim();
    if (normalized.isEmpty || normalized.length > 40) {
      return _failure('invalid_owner_name', 'Enter a valid owner name.');
    }
    final ready = await initialize();
    if (ready case Failed<void>(:final failure)) return Result.failure(failure);
    await stopListening();
    _ownerVerified = false;
    _publish('voice.enrollment.started', {'sample_count': 3});
    const prompts = [
      'Please say: Hello CronyX, this is my voice.',
      'Please say: I am the primary user of this computer.',
      'Please say: CronyX, recognize my voice.',
    ];
    final embeddings = <Float32List>[];
    for (var index = 0; index < prompts.length; index++) {
      final prompt = await speech.speak(prompts[index]);
      if (prompt case Failed<void>(:final failure)) {
        return Result.failure(failure);
      }
      final captured = await _captureUtterance();
      if (captured case Failed<Float32List>(:final failure)) {
        _publish('voice.enrollment.failed', {'failure_code': failure.code});
        return Result.failure(failure);
      }
      final embedding = await runtime.createSpeakerEmbedding(
        (captured as Success<Float32List>).value,
      );
      if (embedding case Failed<Float32List>(:final failure)) {
        _publish('voice.enrollment.failed', {'failure_code': failure.code});
        return Result.failure(failure);
      }
      embeddings.add((embedding as Success<Float32List>).value);
      _publish('voice.enrollment.sample.completed', {'sample': index + 1});
    }
    final profile = OwnerVoiceProfile(
      displayName: normalized,
      embedding: _centroid(embeddings),
      createdAt: clock().toUtc(),
    );
    final saved = await profiles.save(profile);
    if (saved case Failed<void>(:final failure)) return Result.failure(failure);
    _profile = profile;
    _publish('voice.enrollment.completed', {'display_name': normalized});
    await speech.speak('Thanks, $normalized. Your voice profile is ready.');
    return startWakeMonitoring();
  }

  Float32List _centroid(List<Float32List> values) {
    final centroid = Float32List(values.first.length);
    for (final value in values) {
      for (var index = 0; index < centroid.length; index++) {
        centroid[index] += value[index];
      }
    }
    var norm = 0.0;
    for (final value in centroid) {
      norm += value * value;
    }
    norm = math.sqrt(norm);
    if (norm > 0) {
      for (var index = 0; index < centroid.length; index++) {
        centroid[index] /= norm;
      }
    }
    return centroid;
  }

  @override
  Future<Result<void>> resetOwnerProfile() async {
    await stopListening();
    final reset = await profiles.reset();
    if (reset case Failed<void>(:final failure)) return Result.failure(failure);
    _profile = null;
    _ownerVerified = false;
    _publish('voice.profile.reset');
    return const Result.success(null);
  }

  @override
  Future<Result<void>> startWakeMonitoring() async {
    if (_disposed) return _failure('voice_disposed', 'Voice is unavailable.');
    if (_profile == null) {
      return _failure(
        'owner_not_enrolled',
        'An owner voice profile is required.',
      );
    }
    if (_wakeMonitoring || _handlingWake) return const Result.success(null);
    final capture = await microphone.start();
    if (capture case Failed<Stream<Float32List>>(:final failure)) {
      return Result.failure(failure);
    }
    final wakeReset = await runtime.resetWakePhrase();
    if (wakeReset case Failed<void>(:final failure)) {
      await microphone.stop();
      return Result.failure(failure);
    }
    _wakeBuffer.clear();
    _wakeAudioObserved = false;
    _wakeSpeechObserved = false;
    _wakeKeywordDetected = false;
    _wakeSilenceSamples = 0;
    _wakeNoiseCalibrationSamples = 0;
    _wakeNoiseFloor = 0.005;
    _wakeHealthySamples = 0;
    final wakeSession = ++_wakeSession;
    _wakeMonitoring = true;
    _ownerVerified = false;
    _publish('voice.wake.monitoring.started');
    _wakeSubscription = (capture as Success<Stream<Float32List>>).value.listen(
      (samples) => _onWakeSamples(samples, wakeSession),
      onError: (_) => unawaited(
        _recoverWakeCapture(wakeSession, 'microphone_stream_failed'),
      ),
      onDone: () {
        if (wakeSession != _wakeSession) return;
        unawaited(
          _recoverWakeCapture(wakeSession, 'microphone_stream_stopped'),
        );
      },
    );
    return const Result.success(null);
  }

  void _onWakeSamples(Float32List samples, int wakeSession) {
    if (wakeSession != _wakeSession) return;
    _wakeHealthySamples += samples.length;
    if (_wakeHealthySamples >= _sampleRate) _wakeRecoveryAttempts = 0;
    final rms = _rms(samples);
    if (!_wakeAudioObserved && rms >= 0.01) {
      _wakeAudioObserved = true;
      _publish('voice.wake.audio_detected');
    }
    final calibrating =
        _wakeNoiseCalibrationSamples < _sampleRate ~/ 2 &&
        !_wakeSpeechObserved &&
        rms < 0.03;
    if (calibrating) {
      _wakeNoiseFloor = (_wakeNoiseFloor * 0.8) + (rms * 0.2);
      _wakeNoiseCalibrationSamples += samples.length;
    } else {
      final speechThreshold = math.max(0.015, _wakeNoiseFloor * 2.5);
      if (rms >= speechThreshold) {
        _wakeSpeechObserved = true;
        _wakeSilenceSamples = 0;
      } else if (_wakeSpeechObserved) {
        _wakeSilenceSamples += samples.length;
      } else {
        _wakeNoiseFloor = (_wakeNoiseFloor * 0.95) + (rms * 0.05);
      }
    }
    _wakeBuffer.addAll(samples);
    if (_wakeBuffer.length > _wakeBufferSamples) {
      _wakeBuffer.removeRange(0, _wakeBuffer.length - _wakeBufferSamples);
    }
    Float32List? fallbackAudio;
    if (_wakeSpeechObserved &&
        _wakeSilenceSamples >= _wakeFallbackSilenceSamples) {
      fallbackAudio = Float32List.fromList(_wakeBuffer);
      _wakeSpeechObserved = false;
      _wakeSilenceSamples = 0;
    }
    _wakeWork = _wakeWork.then((_) async {
      if (wakeSession != _wakeSession || !_wakeMonitoring || _handlingWake) {
        return;
      }
      final detected = await runtime.detectWakePhrase(samples);
      if (wakeSession != _wakeSession || !_wakeMonitoring) return;
      if (detected case Failed<bool>(:final failure)) {
        _publish('voice.wake.failed', {'failure_code': failure.code});
      }
      if (detected case Success<bool>(value: true)) {
        _wakeKeywordDetected = true;
      }
      if (fallbackAudio != null) {
        final transcript = await runtime.transcribe(fallbackAudio);
        if (wakeSession != _wakeSession || !_wakeMonitoring) return;
        if (transcript case Success<String>(:final value)) {
          final parsed = _parseWakeTranscript(value);
          if (_wakeKeywordDetected || parsed.detected) {
            if (!_wakeKeywordDetected && parsed.detected) {
              _publish('voice.wake.fallback_detected');
            }
            _wakeKeywordDetected = false;
            await _handleWake(fallbackAudio, pendingCommand: parsed.command);
          }
        } else if (_wakeKeywordDetected) {
          _wakeKeywordDetected = false;
          await _handleWake(fallbackAudio);
        }
      }
    });
  }

  ({bool detected, String? command}) _parseWakeTranscript(String transcript) {
    final normalized = transcript
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    const wakeWords = {
      'cronyx',
      'cronix',
      'croney',
      'crowny',
      'crony',
      'trony',
      'coney',
      'corny',
    };
    final words = normalized
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isNotEmpty && words.first == 'hey') words.removeAt(0);
    var detected = false;
    while (words.isNotEmpty && wakeWords.contains(words.first)) {
      detected = true;
      words.removeAt(0);
    }
    if (detected) {
      final command = words.join(' ').trim();
      return (detected: true, command: command.isEmpty ? null : command);
    }
    while (words.isNotEmpty && wakeWords.contains(words.last)) {
      detected = true;
      words.removeLast();
    }
    if (detected) {
      final command = words.join(' ').trim();
      return (detected: true, command: command.isEmpty ? null : command);
    }
    return (detected: false, command: null);
  }

  Future<void> _handleWake(
    Float32List wakeAudio, {
    String? pendingCommand,
  }) async {
    if (_handlingWake) return;
    _handlingWake = true;
    await _stopWakeCapture();
    _publish('voice.wake.detected');
    _publish('voice.verification.started');
    final embedding = await runtime.createSpeakerEmbedding(wakeAudio);
    if (embedding case Failed<Float32List>(:final failure)) {
      _publish('voice.verification.failed', {'failure_code': failure.code});
      _handlingWake = false;
      await _restartWakeMonitoring();
      return;
    }
    final score = _cosine(
      _profile!.embedding,
      (embedding as Success<Float32List>).value,
    );
    if (score < verificationThreshold) {
      await _handleUnknownSpeaker(score);
      _handlingWake = false;
      await _restartWakeMonitoring();
      return;
    }
    _ownerVerified = true;
    _publish('voice.owner.verified', {
      'score': score,
      'threshold': verificationThreshold,
    });
    final pending = _securityEvents
        .where((event) => !event.acknowledged)
        .toList();
    final name = _profile!.displayName;
    if (pending.isNotEmpty) {
      for (final event in pending) {
        event.acknowledged = true;
      }
      _publish('voice.security.events.acknowledged', {'count': pending.length});
      await speech.speak(
        'Hey $name, what can I do for you today? Also, I detected an unrecognized voice while you were away. I kept everything locked.',
      );
    } else if (pendingCommand == null) {
      await speech.speak('Hey $name, what can I do for you today?');
    }
    await _captureAndExecuteOwnerCommand(pendingCommand);
    _ownerVerified = false;
    _handlingWake = false;
    await _restartWakeMonitoring();
  }

  Future<void> _restartWakeMonitoring() async {
    final result = await startWakeMonitoring();
    if (result case Failed<void>(:final failure)) {
      _publish('voice.wake.restart_failed', {'failure_code': failure.code});
    }
  }

  Future<void> _handleUnknownSpeaker(double score) async {
    _ownerVerified = false;
    final event = UnknownSpeakerSessionEvent(
      id: 'unknown-${clock().microsecondsSinceEpoch}',
      occurredAt: clock().toUtc(),
    );
    _securityEvents.add(event);
    _publish('voice.unknown_speaker.detected', {
      'session_event_id': event.id,
      'score': score,
      'threshold': verificationThreshold,
    });
    await speech.speak(
      'I am sorry, I do not recognize your voice. Please state your name for me.',
    );
    final nameAudio = await _captureUtterance();
    if (nameAudio case Success<Float32List>(:final value)) {
      final transcript = await runtime.transcribe(value);
      if (transcript case Success<String>(:final value)) {
        final provided = _shortName(value);
        if (provided.isNotEmpty) event.providedName = provided;
      }
    }
    _publish('voice.access.locked', {'session_event_id': event.id});
    final providedName = event.providedName;
    await speech.speak(
      providedName == null
          ? 'CronyX will remain locked because I could not verify your voice.'
          : 'Hello $providedName. I still cannot verify your voice, so CronyX will remain locked.',
    );
  }

  String _shortName(String transcript) {
    var value = transcript.trim().replaceAll(RegExp(r"[^A-Za-z\-' ]"), '');
    value = value.replaceFirst(
      RegExp(r"^(my name is|i am|i'm)\s+", caseSensitive: false),
      '',
    );
    final parts = value.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    return parts.take(3).join(' ');
  }

  Future<void> _captureAndExecuteOwnerCommand([String? pendingCommand]) async {
    final responseTimer = Stopwatch()..start();
    String transcript;
    if (pendingCommand == null) {
      final captured = await _captureUtterance();
      if (captured case Failed<Float32List>(:final failure)) {
        _publish('voice.stt.failed', {'failure_code': failure.code});
        return;
      }
      _publish('voice.thinking');
      final sttStartedAt = responseTimer.elapsedMilliseconds;
      final recognized = await runtime.transcribe(
        (captured as Success<Float32List>).value,
      );
      diagnostics(
        'voice.latency.stt_ms='
        '${responseTimer.elapsedMilliseconds - sttStartedAt}',
      );
      if (recognized case Failed<String>(:final failure)) {
        _publish('voice.stt.failed', {'failure_code': failure.code});
        await speech.speak('I could not understand that.');
        return;
      }
      transcript = (recognized as Success<String>).value.trim();
    } else {
      _publish('voice.thinking');
      transcript = pendingCommand.trim();
    }
    if (transcript.isEmpty) {
      _publish('voice.stt.empty');
      return;
    }
    _publish('voice.transcript.ready', {'transcript': transcript});
    if (!_ownerVerified) {
      _publish('voice.command.rejected', {'reason': 'voice_locked'});
      return;
    }
    final commandStartedAt = responseTimer.elapsedMilliseconds;
    final result = await commandHandler(transcript);
    diagnostics(
      'voice.latency.command_ms='
      '${responseTimer.elapsedMilliseconds - commandStartedAt}',
    );
    final speechStartedAt = responseTimer.elapsedMilliseconds;
    await result.fold(
      (response) => speech.speak(_spokenResponse(response.message)),
      (failure) => speech.speak(_spokenResponse(failure.message)),
    );
    diagnostics(
      'voice.latency.speech_total_ms='
      '${responseTimer.elapsedMilliseconds - speechStartedAt}',
    );
  }

  /// Keeps host-specific browser results in the UI/event result while using a
  /// stable spoken phrase that can benefit from the local Kokoro cache.
  String _spokenResponse(String message) {
    if (RegExp(
      r'^.+ is opening in CronyX Browser\.$',
      caseSensitive: false,
    ).hasMatch(message)) {
      return 'The page is opening in CronyX Browser.';
    }
    if (RegExp(
      r'^[A-Za-z0-9.-]+\.[A-Za-z]{2,} opened successfully\.$',
      caseSensitive: false,
    ).hasMatch(message)) {
      return 'The website opened successfully.';
    }
    return message;
  }

  Future<Result<Float32List>> _captureUtterance() async {
    final started = await microphone.start();
    if (started case Failed<Stream<Float32List>>(:final failure)) {
      return Result.failure(failure);
    }
    _publish('voice.listening.started');
    final samples = <double>[];
    var speechDetected = false;
    var silenceSamples = 0;
    final completed = Completer<void>();
    late final StreamSubscription<Float32List> subscription;
    final timeout = Timer(const Duration(seconds: 10), () {
      if (!completed.isCompleted) completed.complete();
    });
    subscription = (started as Success<Stream<Float32List>>).value.listen(
      (chunk) {
        samples.addAll(chunk);
        final rms = _rms(chunk);
        if (rms >= 0.015) {
          speechDetected = true;
          silenceSamples = 0;
        } else if (speechDetected) {
          silenceSamples += chunk.length;
        }
        if (speechDetected && silenceSamples >= _endOfSpeechSilenceSamples) {
          if (!completed.isCompleted) completed.complete();
        }
      },
      onError: (_) {
        if (!completed.isCompleted) completed.complete();
      },
      onDone: () {
        if (!completed.isCompleted) completed.complete();
      },
    );
    await completed.future;
    timeout.cancel();
    await subscription.cancel();
    await microphone.stop();
    _publish('voice.listening.stopped');
    if (!speechDetected || samples.length < _sampleRate) {
      return _failure('no_speech', 'No usable speech was captured.');
    }
    return Result.success(Float32List.fromList(samples));
  }

  double _rms(Float32List samples) {
    if (samples.isEmpty) return 0;
    var sum = 0.0;
    for (final sample in samples) {
      sum += sample * sample;
    }
    return math.sqrt(sum / samples.length);
  }

  double _cosine(Float32List left, Float32List right) {
    if (left.length != right.length || left.isEmpty) return -1;
    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;
    for (var index = 0; index < left.length; index++) {
      dot += left[index] * right[index];
      leftNorm += left[index] * left[index];
      rightNorm += right[index] * right[index];
    }
    if (leftNorm == 0 || rightNorm == 0) return -1;
    return dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm));
  }

  @override
  Future<Result<void>> stopListening() async {
    _resumeWakeAfterSpeech = false;
    await _stopWakeCapture();
    await microphone.stop();
    _ownerVerified = false;
    return const Result.success(null);
  }

  Future<void> _stopWakeCapture() async {
    _wakeSession++;
    _wakeMonitoring = false;
    await _wakeSubscription?.cancel();
    _wakeSubscription = null;
    await microphone.stop();
    _publish('voice.wake.monitoring.stopped');
  }

  Future<void> _recoverWakeCapture(int wakeSession, String failureCode) async {
    if (wakeSession != _wakeSession || _disposed || _handlingWake) return;
    _wakeRecoveryAttempts++;
    await _stopWakeCapture();
    _publish('voice.microphone.failed', {'failure_code': failureCode});
    final delay = switch (_wakeRecoveryAttempts) {
      1 => const Duration(milliseconds: 250),
      2 => const Duration(seconds: 1),
      _ => const Duration(seconds: 3),
    };
    await Future<void>.delayed(delay);
    if (!_disposed && !_handlingWake && _profile != null) {
      await _restartWakeMonitoring();
    }
  }

  @override
  Future<Result<String>> describeSecurityActivity() async {
    if (!_ownerVerified) {
      return const Result.failure(
        Failure('Voice access is locked.', code: 'voice_locked'),
      );
    }
    if (_securityEvents.isEmpty) {
      return const Result.success(
        'No unrecognized voice activations were recorded this session.',
      );
    }
    return const Result.success(
      'An unrecognized voice activated the voice interface. No voice commands were executed.',
    );
  }

  Result<T> _failure<T>(String code, String message) =>
      Result.failure(Failure(message, code: code));

  void _publish(String type, [Map<String, Object?> data = const {}]) {
    diagnostics(type == 'voice.startup.readiness' ? '$type $data' : type);
    events.publish(
      ApplicationEvent(type: type, occurredAt: clock().toUtc(), data: data),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stopListening();
    try {
      await _wakeWork;
      await _lifecycleWork;
    } catch (_) {
      // Runtime failures have already been emitted as structured voice events.
    }
    await microphone.dispose();
    await runtime.dispose();
    await _lifecycleSubscription?.cancel();
    _lifecycleSubscription = null;
  }
}
