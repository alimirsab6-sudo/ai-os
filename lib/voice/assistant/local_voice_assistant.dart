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
  static const double _verificationThreshold = 0.72;

  static double get verificationThreshold => _verificationThreshold;

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

  static const int _sampleRate = 16000;

  /// Minimum RMS level considered speech.
  static const double _speechThreshold = 0.015;

  /// Silence required before an utterance is submitted to STT.
  static const int _endOfSpeechSilenceSamples = _sampleRate * 3 ~/ 5;

  /// Maximum amount of audio retained for one utterance.
  static const int _maximumUtteranceSamples = _sampleRate * 10;

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

  final List<UnknownSpeakerSessionEvent> _securityEvents =
      <UnknownSpeakerSessionEvent>[];

  StreamSubscription<Float32List>? _microphoneSubscription;

  final List<double> _speechBuffer = <double>[];

  Future<void> _voiceWork = Future<void>.value();

  StreamSubscription<AppEvent>? _lifecycleSubscription;
  Future<void> _lifecycleWork = Future<void>.value();

  bool _speechDetected = false;
  int _silenceSamples = 0;

  bool _listening = false;
  bool _handlingSpeech = false;

  /*
   * Kept for compatibility with the existing VoiceAssistant interface.
   *
   * Normal voice commands do NOT require speaker verification.
   */
  bool _ownerVerified = false;

  bool _initialized = false;
  bool _disposed = false;
  bool _startupGreetingDelivered = false;
  bool _resumeListeningAfterSpeech = false;

  Future<Result<void>>? _initialization;

  @override
  bool get hasOwnerProfile => _profile != null;

  @override
  bool get ownerVerified => _ownerVerified;

  @override
  bool get wakeMonitoring => _listening;

  @override
  Future<Result<void>> initialize() {
    if (_initialized) {
      return Future<Result<void>>.value(const Result.success(null));
    }

    if (_disposed) {
      return Future<Result<void>>.value(
        _failure('voice_disposed', 'Voice is unavailable.'),
      );
    }

    final current = _initialization;

    if (current != null) {
      return current;
    }

    final task = _initialize();

    _initialization = task;

    unawaited(
      task.then((result) {
        if (result.isFailure) {
          _initialization = null;
        }
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
        ttsReady: true,
      );

      return Result.failure(failure);
    }

    _profile = (loaded as Success<OwnerVoiceProfile?>).value;

    /*
     * Perform a real microphone startup test.
     *
     * An owner profile is NOT required.
     */
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

    if (profile != null) {
      final greeting = await _deliverStartupGreeting(profile.displayName);

      if (greeting case Failed<void>(:final failure)) {
        return Result.failure(failure);
      }
    } else {
      _publish('voice.enrollment.optional');
    }

    /*
     * Start continuous listening.
     *
     * There is NO wake phrase requirement.
     */
    return startWakeMonitoring();
  }

  void _onLifecycleEvent(AppEvent event) {
    /*
     * Stop listening while TTS is speaking.
     *
     * This prevents CronyX from hearing its own voice.
     */
    if (event.type == 'tts.playback.started' && _listening) {
      _resumeListeningAfterSpeech = true;

      _lifecycleWork = _lifecycleWork.then((_) => _stopMicrophoneCapture());

      return;
    }

    if ((event.type == 'tts.playback.completed' ||
            event.type == 'tts.playback.stopped' ||
            event.type == 'tts.failed') &&
        _resumeListeningAfterSpeech) {
      _resumeListeningAfterSpeech = false;

      _lifecycleWork = _lifecycleWork.then((_) async {
        if (!_disposed && !_handlingSpeech) {
          await _restartListening();
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

      /*
         * Speaker verification exists as a subsystem,
         * but it does NOT block normal voice commands.
         */
      'speaker_verification': runtimeReady,

      /*
         * Wake phrase is deliberately disabled.
         */
      'wake_phrase': false,

      'microphone': microphoneReady,
      'owner_profile': profileReady,
      'tts': ttsReady,
    });
  }

  Future<Result<void>> _deliverStartupGreeting(String name) async {
    if (_startupGreetingDelivered) {
      return const Result.success(null);
    }

    _startupGreetingDelivered = true;

    final greeting = _timeGreeting(clock().hour);

    _publish('voice.startup.greeting', {'display_name': name});

    final result = await speech.speak(
      '$greeting, $name. CronyX is online. '
      'Voice systems are ready.',
    );

    _publish('voice.startup.completed', {'audio_playback': result.isSuccess});

    return result;
  }

  static String _timeGreeting(int hour) {
    if (hour < 12) {
      return 'Good morning';
    }

    if (hour < 17) {
      return 'Good afternoon';
    }

    return 'Good evening';
  }

  @override
  Future<Result<void>> enrollOwner(String displayName) async {
    final normalized = displayName.trim();

    if (normalized.isEmpty || normalized.length > 40) {
      return _failure('invalid_owner_name', 'Enter a valid owner name.');
    }

    final ready = await initialize();

    if (ready case Failed<void>(:final failure)) {
      return Result.failure(failure);
    }

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

    if (saved case Failed<void>(:final failure)) {
      return Result.failure(failure);
    }

    _profile = profile;

    _publish('voice.enrollment.completed', {'display_name': normalized});

    await speech.speak(
      'Thanks, $normalized. '
      'Your voice profile is ready.',
    );

    return startWakeMonitoring();
  }

  Float32List _centroid(List<Float32List> values) {
    if (values.isEmpty) {
      return Float32List(0);
    }

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

    if (reset case Failed<void>(:final failure)) {
      return Result.failure(failure);
    }

    _profile = null;
    _ownerVerified = false;

    _publish('voice.profile.reset');

    /*
     * Resetting the profile does NOT disable
     * normal conversation.
     */
    await startWakeMonitoring();

    return const Result.success(null);
  }

  /*
   * The existing interface calls this
   * startWakeMonitoring().
   *
   * It is now continuous listening.
   *
   * NO wake word is checked.
   */
  @override
  Future<Result<void>> startWakeMonitoring() async {
    if (_disposed) {
      return _failure('voice_disposed', 'Voice is unavailable.');
    }

    if (_listening || _handlingSpeech) {
      return const Result.success(null);
    }

    diagnostics('voice.listen.start_requested');

    final capture = await microphone.start();

    if (capture case Failed<Stream<Float32List>>(:final failure)) {
      diagnostics(
        'voice.listen.start_failed '
        'code=${failure.code}',
      );

      return Result.failure(failure);
    }

    _speechBuffer.clear();
    _speechDetected = false;
    _silenceSamples = 0;

    final session = DateTime.now().microsecondsSinceEpoch;

    _listening = true;

    /*
     * Compatibility state only.
     *
     * It does not authorize/deny commands.
     */
    _ownerVerified = true;

    _publish('voice.wake.monitoring.started', {
      'mode': 'continuous_listening',
      'wake_word_required': false,
    });

    _publish('voice.listening.ready');

    _microphoneSubscription = (capture as Success<Stream<Float32List>>).value
        .listen(
          (samples) {
            _onMicrophoneSamples(samples, session);
          },
          onError: (Object error, StackTrace stack) {
            diagnostics(
              'voice.microphone.stream_error '
              '$error',
            );

            _publish('voice.microphone.failed', {
              'failure_code': 'microphone_stream_failed',
            });
          },
          onDone: () {
            diagnostics('voice.microphone.stream_closed');

            if (_listening && !_handlingSpeech && !_disposed) {
              unawaited(_restartListening());
            }
          },
        );

    diagnostics(
      'voice.listen.started '
      'mode=continuous '
      'wake_word=false',
    );

    return const Result.success(null);
  }

  void _onMicrophoneSamples(Float32List samples, int session) {
    if (!_listening || _handlingSpeech || _disposed) {
      return;
    }

    if (samples.isEmpty) {
      return;
    }

    final rms = _rms(samples);

    if (rms >= _speechThreshold) {
      if (!_speechDetected) {
        _speechDetected = true;
        _silenceSamples = 0;

        _publish('voice.speech.detected', {'rms': rms});

        diagnostics(
          'voice.speech.started '
          'rms=$rms',
        );
      } else {
        _silenceSamples = 0;
      }
    } else if (_speechDetected) {
      _silenceSamples += samples.length;
    }

    if (_speechDetected) {
      _speechBuffer.addAll(samples);

      if (_speechBuffer.length > _maximumUtteranceSamples) {
        _speechBuffer.removeRange(
          0,
          _speechBuffer.length - _maximumUtteranceSamples,
        );
      }
    }

    if (_speechDetected && _silenceSamples >= _endOfSpeechSilenceSamples) {
      final audio = Float32List.fromList(_speechBuffer);

      _speechBuffer.clear();
      _speechDetected = false;
      _silenceSamples = 0;

      /*
       * Ignore extremely short noises.
       */
      if (audio.length >= _sampleRate ~/ 4) {
        unawaited(_processSpeech(audio));
      }
    }
  }

  Future<void> _processSpeech(Float32List audio) async {
    if (_handlingSpeech || _disposed) {
      return;
    }

    _handlingSpeech = true;

    await _stopMicrophoneCapture();

    _publish('voice.listening.stopped');

    diagnostics(
      'voice.stt.start '
      'samples=${audio.length} '
      'seconds=${audio.length / _sampleRate}',
    );

    final timer = Stopwatch()..start();

    final transcript = await runtime.transcribe(audio);

    diagnostics(
      'voice.stt.elapsed_ms='
      '${timer.elapsedMilliseconds}',
    );

    if (transcript case Failed<String>(:final failure)) {
      _publish('voice.stt.failed', {'failure_code': failure.code});

      await speech.speak('I could not understand that.');

      _handlingSpeech = false;

      await _restartListening();

      return;
    }

    final text = (transcript as Success<String>).value.trim();

    if (text.isEmpty) {
      _publish('voice.stt.empty');

      _handlingSpeech = false;

      await _restartListening();

      return;
    }

    diagnostics('voice.stt.transcript="$text"');

    _publish('voice.transcript.ready', {'transcript': text});

    /*
     * THIS IS THE IMPORTANT PART.
     *
     * There is:
     *
     * NO Crony check
     * NO CronyX check
     * NO wake-word parser
     * NO speaker verification
     * NO owner profile check
     *
     * Every recognized sentence goes
     * directly to the orchestrator.
     */

    _ownerVerified = true;

    _publish('voice.command.accepted', {'reason': 'continuous_voice_mode'});

    _publish('voice.thinking');

    final commandTimer = Stopwatch()..start();

    Result<OrchestratorResponse> result;

    try {
      result = await commandHandler(text);
    } catch (error, stack) {
      diagnostics(
        'voice.command.exception '
        '$error\n$stack',
      );

      _publish('voice.command.failed', {'failure_code': 'command_exception'});

      await speech.speak('Something went wrong while processing that request.');

      _handlingSpeech = false;
      _ownerVerified = true;

      await _restartListening();

      return;
    }

    diagnostics(
      'voice.command.elapsed_ms='
      '${commandTimer.elapsedMilliseconds}',
    );

    final speechTimer = Stopwatch()..start();

    await result.fold(
      (response) async {
        final message = _spokenResponse(response.message);

        diagnostics('voice.response="$message"');

        _publish('voice.response.ready', {'message': message});

        await speech.speak(message);
      },
      (failure) async {
        diagnostics(
          'voice.command.failure '
          '${failure.code}: '
          '${failure.message}',
        );

        _publish('voice.command.failed', {'failure_code': failure.code});

        await speech.speak(_spokenResponse(failure.message));
      },
    );

    diagnostics(
      'voice.response.speech_elapsed_ms='
      '${speechTimer.elapsedMilliseconds}',
    );

    _handlingSpeech = false;
    _ownerVerified = true;

    await _restartListening();
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
      if (!completed.isCompleted) {
        completed.complete();
      }
    });

    subscription = (started as Success<Stream<Float32List>>).value.listen(
      (chunk) {
        samples.addAll(chunk);

        final rms = _rms(chunk);

        if (rms >= _speechThreshold) {
          speechDetected = true;
          silenceSamples = 0;
        } else if (speechDetected) {
          silenceSamples += chunk.length;
        }

        if (speechDetected && silenceSamples >= _endOfSpeechSilenceSamples) {
          if (!completed.isCompleted) {
            completed.complete();
          }
        }
      },
      onError: (_) {
        if (!completed.isCompleted) {
          completed.complete();
        }
      },
      onDone: () {
        if (!completed.isCompleted) {
          completed.complete();
        }
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

  double _rms(Float32List samples) {
    if (samples.isEmpty) {
      return 0;
    }

    var sum = 0.0;

    for (final sample in samples) {
      sum += sample * sample;
    }

    return math.sqrt(sum / samples.length);
  }

  @override
  Future<Result<void>> stopListening() async {
    _resumeListeningAfterSpeech = false;

    await _stopMicrophoneCapture();

    _ownerVerified = false;

    return const Result.success(null);
  }

  Future<void> _stopMicrophoneCapture() async {
    _listening = false;

    await _microphoneSubscription?.cancel();

    _microphoneSubscription = null;

    await microphone.stop();

    _speechBuffer.clear();
    _speechDetected = false;
    _silenceSamples = 0;

    _publish('voice.wake.monitoring.stopped');
  }

  Future<void> _restartListening() async {
    if (_disposed || _handlingSpeech) {
      return;
    }

    /*
     * Give TTS/player lifecycle time to
     * settle before reopening the mic.
     */
    await Future<void>.delayed(const Duration(milliseconds: 150));

    if (_disposed || _handlingSpeech) {
      return;
    }

    final result = await startWakeMonitoring();

    if (result case Failed<void>(:final failure)) {
      diagnostics(
        'voice.listen.restart_failed '
        'code=${failure.code}',
      );

      _publish('voice.microphone.failed', {'failure_code': failure.code});
    }
  }

  @override
  Future<Result<String>> describeSecurityActivity() async {
    if (_securityEvents.isEmpty) {
      return const Result.success(
        'No unrecognized voice activations were recorded this session.',
      );
    }

    return const Result.success(
      'An unrecognized voice activation was recorded. Normal voice conversation is currently enabled.',
    );
  }

  Result<T> _failure<T>(String code, String message) {
    return Result.failure(Failure(message, code: code));
  }

  void _publish(String type, [Map<String, Object?> data = const {}]) {
    if (type == 'voice.startup.readiness') {
      diagnostics('$type $data');
    } else {
      diagnostics(type);
    }

    events.publish(
      ApplicationEvent(type: type, occurredAt: clock().toUtc(), data: data),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await stopListening();

    try {
      await _voiceWork;
      await _lifecycleWork;
    } catch (_) {
      // Runtime failures are emitted as structured events.
    }

    await microphone.dispose();

    await runtime.dispose();

    await _lifecycleSubscription?.cancel();

    _lifecycleSubscription = null;
  }
}


