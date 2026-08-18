import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/result.dart';
import '../audio/wav_audio_inspector.dart';
import 'kokoro_bridge.dart';

abstract interface class KokoroRuntimeProcess {
  Stream<String> get stdoutLines;
  Stream<String> get stderrLines;
  Future<int> get exitCode;

  void writeLine(String line);
  Future<void> closeInput();
  bool kill();
}

abstract interface class KokoroRuntimeProcessLauncher {
  Future<Result<KokoroRuntimeProcess>> start();
}

final class FixedNodeKokoroProcessLauncher
    implements KokoroRuntimeProcessLauncher {
  FixedNodeKokoroProcessLauncher({String? projectRoot, String? nodeExecutable})
    : projectRoot = projectRoot ?? Directory.current.path,
      nodeExecutable =
          nodeExecutable ??
          '${Platform.environment['ProgramFiles'] ?? r'C:\Program Files'}'
              r'\nodejs\node.exe';

  final String projectRoot;
  final String nodeExecutable;

  String get runtimeDirectory =>
      '$projectRoot${Platform.pathSeparator}runtime${Platform.pathSeparator}'
      'kokoro${Platform.pathSeparator}runtime${Platform.pathSeparator}node';

  String get bridgeEntrypoint =>
      '$runtimeDirectory${Platform.pathSeparator}bridge.mjs';

  @override
  Future<Result<KokoroRuntimeProcess>> start() async {
    if (!Platform.isWindows ||
        !File(nodeExecutable).existsSync() ||
        !File(bridgeEntrypoint).existsSync()) {
      return const Result.failure(
        Failure(
          'The local Kokoro runtime is unavailable.',
          code: 'kokoro_runtime_unavailable',
        ),
      );
    }
    try {
      final process = await Process.start(
        nodeExecutable,
        [bridgeEntrypoint],
        workingDirectory: runtimeDirectory,
        mode: ProcessStartMode.normal,
        runInShell: false,
      );
      return Result.success(_DartIoKokoroRuntimeProcess(process));
    } catch (_) {
      return const Result.failure(
        Failure(
          'The local Kokoro runtime could not be started.',
          code: 'kokoro_process_failed',
        ),
      );
    }
  }
}

final class _DartIoKokoroRuntimeProcess implements KokoroRuntimeProcess {
  _DartIoKokoroRuntimeProcess(this._process);

  final Process _process;

  @override
  Stream<String> get stdoutLines =>
      _process.stdout.transform(utf8.decoder).transform(const LineSplitter());

  @override
  Stream<String> get stderrLines =>
      _process.stderr.transform(utf8.decoder).transform(const LineSplitter());

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void writeLine(String line) => _process.stdin.writeln(line);

  @override
  Future<void> closeInput() => _process.stdin.close();

  @override
  bool kill() => _process.kill();
}

/// Persistent JSON-lines bridge to the fixed, application-owned Node entrypoint.
final class NodeKokoroBridge implements KokoroBridge {
  NodeKokoroBridge({
    required this.launcher,
    required this.allowedOutputDirectory,
    this.startupTimeout = const Duration(seconds: 30),
    this.wavInspector = const WavAudioInspector(),
    void Function(String message)? diagnostics,
  }) : diagnostics = diagnostics ?? _noDiagnostics;

  final KokoroRuntimeProcessLauncher launcher;
  final String allowedOutputDirectory;
  final Duration startupTimeout;
  final WavAudioInspector wavInspector;
  final void Function(String message) diagnostics;

  static void _noDiagnostics(String _) {}

  KokoroRuntimeProcess? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Completer<Result<void>>? _ready;
  final Map<String, Completer<Result<KokoroAudioArtifact>>> _pending = {};
  final Map<String, int> _requestSentAt = {};
  bool _initialized = false;
  bool _disposed = false;

  @override
  Future<Result<void>> initialize() async {
    if (_disposed) {
      return const Result.failure(
        Failure('The Kokoro bridge is disposed.', code: 'kokoro_disposed'),
      );
    }
    if (_initialized) return const Result.success(null);
    final existing = _ready;
    if (existing != null) return existing.future;

    final ready = _ready = Completer<Result<void>>();
    final launchResult = await launcher.start();
    if (launchResult case Failed<KokoroRuntimeProcess>(:final failure)) {
      ready.complete(Result.failure(failure));
      return ready.future;
    }

    final process = (launchResult as Success<KokoroRuntimeProcess>).value;
    diagnostics('runtime_process_started');
    _process = process;
    _stdoutSubscription = process.stdoutLines.listen(
      _handleStdoutLine,
      onError: (_) => _failProcess('kokoro_process_failed'),
      onDone: () => _failProcess('kokoro_process_ended'),
    );
    _stderrSubscription = process.stderrLines.listen(
      (line) => diagnostics('runtime_stderr $line'),
    );
    unawaited(
      process.exitCode.then((_) => _failProcess('kokoro_process_ended')),
    );

    try {
      return await ready.future.timeout(startupTimeout);
    } on TimeoutException {
      await dispose();
      return const Result.failure(
        Failure(
          'The local Kokoro runtime did not become ready.',
          code: 'kokoro_startup_timeout',
        ),
      );
    }
  }

  @override
  Future<Result<KokoroAudioArtifact>> synthesize(
    KokoroBridgeRequest request,
  ) async {
    final validation = KokoroBridgeRequest.fromJson(request.toJson());
    if (validation is Failed<KokoroBridgeRequest>) {
      return Result.failure(validation.failure);
    }
    final initialized = await initialize();
    if (initialized case Failed<void>(:final failure)) {
      return Result.failure(failure);
    }
    final process = _process;
    if (process == null || _disposed) {
      return const Result.failure(
        Failure(
          'The local Kokoro runtime is unavailable.',
          code: 'kokoro_runtime_unavailable',
        ),
      );
    }

    final completion = Completer<Result<KokoroAudioArtifact>>();
    _pending[request.id] = completion;
    try {
      final sentAt = DateTime.now().microsecondsSinceEpoch;
      _requestSentAt[request.id] = sentAt;
      final requestToNodeMilliseconds = request.createdAtEpochMicroseconds == 0
          ? 0
          : (sentAt - request.createdAtEpochMicroseconds) / 1000;
      diagnostics(
        '[TTS:${request.id}] T0->T1 request_to_node '
        '${requestToNodeMilliseconds.toStringAsFixed(1)} ms',
      );
      process.writeLine(
        jsonEncode({...request.toJson(), 'sent_at_epoch_us': sentAt}),
      );
    } catch (_) {
      _pending.remove(request.id);
      _requestSentAt.remove(request.id);
      return const Result.failure(
        Failure(
          'The Kokoro request could not be sent.',
          code: 'kokoro_process_failed',
        ),
      );
    }
    return completion.future;
  }

  void _handleStdoutLine(String line) {
    Map<String, Object?> message;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, Object?>) return;
      message = decoded;
    } catch (_) {
      return;
    }

    if (message['type'] == 'ready') {
      _initialized = true;
      diagnostics('runtime_ready');
      final ready = _ready;
      if (ready != null && !ready.isCompleted) {
        ready.complete(const Result.success(null));
      }
      return;
    }

    final id = message['id'];
    if (id is! String) return;
    final completion = _pending.remove(id);
    if (completion == null || completion.isCompleted) return;
    final sentAt = _requestSentAt.remove(id) ?? 0;
    final flutterReceivedAt = DateTime.now().microsecondsSinceEpoch;
    if (message['ok'] != true) {
      completion.complete(
        Result.failure(
          Failure(
            'Local speech generation failed.',
            code: message['error_code'] as String? ?? 'kokoro_failed',
          ),
        ),
      );
      return;
    }

    final path = message['audio_path'];
    final sampleRate = message['sample_rate'];
    final channels = message['channels'];
    final bitsPerSample = message['bits_per_sample'];
    final timing = message['timing'];
    if (path is! String ||
        sampleRate is! int ||
        channels is! int ||
        bitsPerSample is! int ||
        timing is! Map<String, Object?> ||
        !_isAllowedOutput(path)) {
      completion.complete(
        const Result.failure(
          Failure('The Kokoro response is invalid.', code: 'invalid_response'),
        ),
      );
      return;
    }
    final nodeReceivedEpochMilliseconds = timing['node_received_epoch_ms'];
    final nodeQueueMilliseconds = timing['node_queue_ms'];
    final inferenceMilliseconds = timing['inference_ms'];
    final wavWriteMilliseconds = timing['wav_write_ms'];
    final nodeTotalMilliseconds = timing['node_total_ms'];
    final cacheHit = timing['cache_hit'];
    if (nodeReceivedEpochMilliseconds is! int ||
        nodeQueueMilliseconds is! num ||
        inferenceMilliseconds is! num ||
        wavWriteMilliseconds is! num ||
        nodeTotalMilliseconds is! num ||
        cacheHit is! bool) {
      completion.complete(
        const Result.failure(
          Failure(
            'The Kokoro timing response is invalid.',
            code: 'invalid_response',
          ),
        ),
      );
      return;
    }
    final rawNodeTransportMilliseconds = sentAt == 0
        ? 0
        : nodeReceivedEpochMilliseconds - sentAt / 1000;
    final rawFlutterTransportMilliseconds =
        flutterReceivedAt / 1000 -
        (nodeReceivedEpochMilliseconds + nodeTotalMilliseconds);
    final nodeTransportMilliseconds = rawNodeTransportMilliseconds < 0
        ? 0.0
        : rawNodeTransportMilliseconds;
    final flutterTransportMilliseconds = rawFlutterTransportMilliseconds < 0
        ? 0.0
        : rawFlutterTransportMilliseconds;
    diagnostics(
      '[TTS:$id] T1->T2 node_transport '
      '${nodeTransportMilliseconds.toStringAsFixed(1)} ms',
    );
    diagnostics(
      '[TTS:$id] T2->T3 node_queue '
      '${nodeQueueMilliseconds.toStringAsFixed(1)} ms',
    );
    diagnostics(
      '[TTS:$id] T3->T4 kokoro_inference '
      '${inferenceMilliseconds.toStringAsFixed(1)} ms '
      'cache_hit=$cacheHit',
    );
    diagnostics(
      '[TTS:$id] T4->T5 wav_write '
      '${wavWriteMilliseconds.toStringAsFixed(1)} ms',
    );
    diagnostics(
      '[TTS:$id] T5->T6 flutter_receive '
      '${flutterTransportMilliseconds.toStringAsFixed(1)} ms',
    );
    unawaited(
      _validateAudioArtifact(
        completion: completion,
        path: path,
        sampleRate: sampleRate,
        channels: channels,
        bitsPerSample: bitsPerSample,
        nodeQueueMilliseconds: nodeQueueMilliseconds.toDouble(),
        inferenceMilliseconds: inferenceMilliseconds.toDouble(),
        wavWriteMilliseconds: wavWriteMilliseconds.toDouble(),
        nodeTotalMilliseconds: nodeTotalMilliseconds.toDouble(),
        flutterReceivedAtEpochMicroseconds: flutterReceivedAt,
        cacheHit: cacheHit,
      ),
    );
  }

  Future<void> _validateAudioArtifact({
    required Completer<Result<KokoroAudioArtifact>> completion,
    required String path,
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
    required double nodeQueueMilliseconds,
    required double inferenceMilliseconds,
    required double wavWriteMilliseconds,
    required double nodeTotalMilliseconds,
    required int flutterReceivedAtEpochMicroseconds,
    required bool cacheHit,
  }) async {
    final inspected = await wavInspector.inspect(path);
    if (completion.isCompleted) return;
    if (inspected case Failed<WavAudioMetadata>(:final failure)) {
      diagnostics('audio_validation_failed code=${failure.code}');
      completion.complete(Result.failure(failure));
      return;
    }
    final metadata = (inspected as Success<WavAudioMetadata>).value;
    if (metadata.sampleRate != sampleRate ||
        metadata.channels != channels ||
        metadata.bitsPerSample != bitsPerSample ||
        metadata.formatTag != 3 ||
        !metadata.containsAudio) {
      diagnostics('audio_validation_failed code=invalid_audio_artifact');
      completion.complete(
        const Result.failure(
          Failure(
            'Generated speech audio is invalid or silent.',
            code: 'invalid_audio_artifact',
          ),
        ),
      );
      return;
    }
    diagnostics(
      'audio_generated path=$path bytes=${metadata.fileSize} '
      'format=${metadata.formatTag} rate=${metadata.sampleRate} '
      'channels=${metadata.channels} bits=${metadata.bitsPerSample} '
      'nonzero=${metadata.nonZeroSampleCount}',
    );
    completion.complete(
      Result.success(
        KokoroAudioArtifact(
          filePath: path,
          sampleRate: metadata.sampleRate,
          channels: metadata.channels,
          bitsPerSample: metadata.bitsPerSample,
          formatTag: metadata.formatTag,
          fileSize: metadata.fileSize,
          nonZeroSampleCount: metadata.nonZeroSampleCount,
          nodeQueueMilliseconds: nodeQueueMilliseconds,
          inferenceMilliseconds: inferenceMilliseconds,
          wavWriteMilliseconds: wavWriteMilliseconds,
          nodeTotalMilliseconds: nodeTotalMilliseconds,
          flutterReceivedAtEpochMicroseconds:
              flutterReceivedAtEpochMicroseconds,
          cacheHit: cacheHit,
        ),
      ),
    );
  }

  bool _isAllowedOutput(String filePath) {
    final root = Directory(allowedOutputDirectory).absolute.path.toLowerCase();
    final candidate = File(filePath).absolute.path.toLowerCase();
    return candidate.startsWith('$root${Platform.pathSeparator}') &&
        candidate.endsWith('.wav');
  }

  void _failProcess(String code) {
    if (_disposed) return;
    _initialized = false;
    final failure = Failure(
      'The local Kokoro process stopped unexpectedly.',
      code: code,
    );
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.complete(Result.failure(failure));
    }
    for (final completion in _pending.values) {
      if (!completion.isCompleted) {
        completion.complete(Result.failure(failure));
      }
    }
    _pending.clear();
    _requestSentAt.clear();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final completion in _pending.values) {
      if (!completion.isCompleted) {
        completion.complete(
          const Result.failure(
            Failure('Speech was stopped.', code: 'speech_stopped'),
          ),
        );
      }
    }
    _pending.clear();
    _requestSentAt.clear();
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    final process = _process;
    _process = null;
    if (process != null) {
      try {
        await process.closeInput();
      } catch (_) {
        // The process may already have exited.
      }
      process.kill();
    }
  }
}
