import 'dart:async';
import 'dart:convert';

import 'package:ai_os/core/events/app_event.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/voice/audio/speech_audio_player.dart';
import 'package:ai_os/voice/kokoro/kokoro_bridge.dart';
import 'package:ai_os/voice/kokoro/node_kokoro_bridge.dart';
import 'package:ai_os/voice/speech_synthesizer.dart';

final class FakeKokoroBridge implements KokoroBridge {
  Result<void> initializeResult = const Result.success(null);
  Failure? synthesisFailure;
  int initializeCount = 0;
  int disposeCount = 0;
  final List<KokoroBridgeRequest> requests = [];

  @override
  Future<Result<void>> initialize() async {
    initializeCount++;
    return initializeResult;
  }

  @override
  Future<Result<KokoroAudioArtifact>> synthesize(
    KokoroBridgeRequest request,
  ) async {
    requests.add(request);
    final failure = synthesisFailure;
    if (failure != null) return Result.failure(failure);
    return const Result.success(
      KokoroAudioArtifact(
        filePath: r'C:\ai-os\runtime\kokoro\output\bridge\speech.wav',
        sampleRate: 24000,
        channels: 1,
        bitsPerSample: 32,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

final class FakeSpeechAudioPlayer implements SpeechAudioPlayer {
  FakeSpeechAudioPlayer({this.autoComplete = true});

  final bool autoComplete;
  Failure? playFailure;
  int playCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  int activePlaybacks = 0;
  int maximumConcurrentPlaybacks = 0;
  Completer<Result<void>>? _completion;

  @override
  Future<Result<void>> play(
    String filePath, {
    required void Function() onStarted,
  }) async {
    playCount++;
    activePlaybacks++;
    if (activePlaybacks > maximumConcurrentPlaybacks) {
      maximumConcurrentPlaybacks = activePlaybacks;
    }
    onStarted();
    final failure = playFailure;
    if (failure != null) {
      activePlaybacks--;
      return Result.failure(failure);
    }
    if (autoComplete) {
      activePlaybacks--;
      return const Result.success(null);
    }
    final completion = _completion = Completer<Result<void>>();
    final result = await completion.future;
    activePlaybacks--;
    return result;
  }

  void complete() {
    final completion = _completion;
    if (completion != null && !completion.isCompleted) {
      completion.complete(const Result.success(null));
    }
  }

  @override
  Future<void> stop() async {
    stopCount++;
    final completion = _completion;
    _completion = null;
    if (completion != null && !completion.isCompleted) {
      completion.complete(
        const Result.failure(Failure('Stopped.', code: 'speech_stopped')),
      );
    }
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    await stop();
  }
}

final class FakeSpeechSynthesizer implements SpeechSynthesizer {
  FakeSpeechSynthesizer({
    required this.events,
    this.failSpeech = false,
    this.completeImmediately = false,
  });

  final EventBus events;
  final bool failSpeech;
  final bool completeImmediately;
  int initializeCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  final List<String> spokenTexts = [];
  Completer<Result<void>>? _completion;

  @override
  Future<Result<void>> initialize() async {
    initializeCount++;
    return const Result.success(null);
  }

  @override
  Future<Result<void>> speak(String text) async {
    spokenTexts.add(text);
    if (failSpeech) {
      _publish('tts.failed', {'stage': 'generation'});
      return const Result.failure(
        Failure('Voice failed.', code: 'kokoro_failed'),
      );
    }
    _publish('tts.playback.started');
    if (completeImmediately) {
      _publish('tts.playback.completed');
      return const Result.success(null);
    }
    final completion = _completion = Completer<Result<void>>();
    return completion.future;
  }

  void completePlayback() {
    _publish('tts.playback.completed');
    final completion = _completion;
    if (completion != null && !completion.isCompleted) {
      completion.complete(const Result.success(null));
    }
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _publish('tts.playback.stopped');
    final completion = _completion;
    if (completion != null && !completion.isCompleted) {
      completion.complete(
        const Result.failure(Failure('Stopped.', code: 'speech_stopped')),
      );
    }
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
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

final class FakeKokoroRuntimeProcess implements KokoroRuntimeProcess {
  final StreamController<String> stdoutController = StreamController.broadcast(
    sync: true,
  );
  final StreamController<String> stderrController = StreamController.broadcast(
    sync: true,
  );
  final Completer<int> exitCompleter = Completer<int>();
  final List<String> writtenLines = [];
  bool killed = false;

  @override
  Stream<String> get stdoutLines => stdoutController.stream;

  @override
  Stream<String> get stderrLines => stderrController.stream;

  @override
  Future<int> get exitCode => exitCompleter.future;

  @override
  void writeLine(String line) => writtenLines.add(line);

  Map<String, Object?> get lastWrittenJson =>
      jsonDecode(writtenLines.last) as Map<String, Object?>;

  @override
  Future<void> closeInput() async {}

  @override
  bool kill() {
    killed = true;
    if (!exitCompleter.isCompleted) exitCompleter.complete(-1);
    return true;
  }
}

final class FakeKokoroRuntimeProcessLauncher
    implements KokoroRuntimeProcessLauncher {
  FakeKokoroRuntimeProcessLauncher.success(this.process) : failure = null;

  FakeKokoroRuntimeProcessLauncher.failure(this.failure) : process = null;

  final FakeKokoroRuntimeProcess? process;
  final Failure? failure;
  int startCount = 0;

  @override
  Future<Result<KokoroRuntimeProcess>> start() async {
    startCount++;
    final launchFailure = failure;
    if (launchFailure != null) return Result.failure(launchFailure);
    return Result.success(process!);
  }
}

