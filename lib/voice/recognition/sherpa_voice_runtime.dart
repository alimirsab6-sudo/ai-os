import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/result.dart';
import 'local_voice_runtime.dart';

final class SherpaVoiceRuntime implements LocalVoiceRuntime {
  SherpaVoiceRuntime({required this.paths});

  final VoiceRuntimePaths paths;
  final Map<int, Completer<Map<Object?, Object?>>> _pending = {};
  ReceivePort? _responses;
  StreamSubscription<Object?>? _responseSubscription;
  SendPort? _commands;
  Isolate? _isolate;
  Future<Result<void>>? _initialization;
  var _nextId = 0;

  @override
  Future<Result<void>> initialize() {
    final current = _initialization;
    if (current != null) return current;
    return _initialization = _start();
  }

  Future<Result<void>> _start() async {
    final missing = paths.requiredFiles
        .where((path) => !File(path).existsSync())
        .toList(growable: false);
    if (missing.isNotEmpty) {
      _initialization = null;
      return const Result.failure(
        Failure(
          'Local voice model files are missing.',
          code: 'voice_models_missing',
        ),
      );
    }
    try {
      final responses = ReceivePort();
      _responses = responses;
      final ready = Completer<SendPort>();
      _responseSubscription = responses.listen((message) {
        if (message is SendPort) {
          if (!ready.isCompleted) ready.complete(message);
          return;
        }
        if (message is! Map<Object?, Object?>) return;
        final id = message['id'];
        if (id is int) _pending.remove(id)?.complete(message);
      });
      _isolate = await Isolate.spawn(_voiceWorker, responses.sendPort);
      _commands = await ready.future;
      final initialized = await _request('initialize', {
        'moonshine_root': paths.moonshineRoot,
        'keyword_root': paths.keywordRoot,
        'speaker_model': paths.speakerModel,
        'keyword_file': paths.keywordFile,
      });
      if (initialized case Failed<Object?>(:final failure)) {
        await dispose();
        _initialization = null;
        return Result.failure(failure);
      }
      return const Result.success(null);
    } catch (_) {
      await dispose();
      _initialization = null;
      return const Result.failure(
        Failure(
          'The local voice runtime could not start.',
          code: 'voice_runtime_failed',
        ),
      );
    }
  }

  @override
  Future<Result<String>> transcribe(Float32List samples) async {
    final result = await _audioRequest('transcribe', samples);
    return result.fold(
      (value) => value is String
          ? Result.success(value.trim())
          : const Result.failure(
              Failure(
                'Speech recognition returned invalid data.',
                code: 'stt_failed',
              ),
            ),
      Result.failure,
    );
  }

  @override
  Future<Result<Float32List>> createSpeakerEmbedding(
    Float32List samples,
  ) async {
    final result = await _audioRequest('speaker_embedding', samples);
    return result.fold(
      (value) => value is Float32List
          ? Result.success(value)
          : const Result.failure(
              Failure(
                'Speaker verification returned invalid data.',
                code: 'speaker_failed',
              ),
            ),
      Result.failure,
    );
  }

  @override
  Future<Result<bool>> detectWakePhrase(Float32List samples) async {
    final result = await _audioRequest('wake_chunk', samples);
    return result.fold(
      (value) => value is bool
          ? Result.success(value)
          : const Result.failure(
              Failure(
                'Wake detection returned invalid data.',
                code: 'wake_failed',
              ),
            ),
      Result.failure,
    );
  }

  @override
  Future<Result<void>> resetWakePhrase() async {
    final result = await _request('wake_reset');
    return result.fold((_) => const Result.success(null), Result.failure);
  }

  Future<Result<Object?>> _audioRequest(
    String operation,
    Float32List samples,
  ) => _request(operation, {'samples': samples});

  Future<Result<Object?>> _request(
    String operation, [
    Map<String, Object?> data = const {},
  ]) async {
    if (_commands == null && operation != 'initialize') {
      final ready = await initialize();
      if (ready case Failed<void>(:final failure)) {
        return Result.failure(failure);
      }
    }
    final commands = _commands;
    if (commands == null) {
      return const Result.failure(
        Failure(
          'The local voice runtime is unavailable.',
          code: 'voice_runtime_unavailable',
        ),
      );
    }
    final id = ++_nextId;
    final completer = Completer<Map<Object?, Object?>>();
    _pending[id] = completer;
    commands.send({'id': id, 'operation': operation, ...data});
    final response = await completer.future;
    if (response['ok'] == true) return Result.success(response['value']);
    return Result.failure(
      Failure(
        response['message'] as String? ?? 'Local voice processing failed.',
        code: response['code'] as String? ?? 'voice_runtime_failed',
      ),
    );
  }

  @override
  Future<void> dispose() async {
    final commands = _commands;
    if (commands != null) {
      try {
        await _request('dispose');
      } catch (_) {}
    }
    _commands = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.complete({'ok': false, 'code': 'voice_runtime_disposed'});
      }
    }
    _pending.clear();
    await _responseSubscription?.cancel();
    _responseSubscription = null;
    _responses?.close();
    _responses = null;
    _initialization = null;
  }
}

void _voiceWorker(SendPort responses) {
  final commands = ReceivePort();
  responses.send(commands.sendPort);
  sherpa.OfflineRecognizer? recognizer;
  sherpa.SpeakerEmbeddingExtractor? extractor;
  sherpa.KeywordSpotter? spotter;
  sherpa.OnlineStream? keywordStream;

  commands.listen((message) {
    if (message is! Map<Object?, Object?>) return;
    final id = message['id'] as int;
    final operation = message['operation'] as String;
    try {
      Object? value;
      switch (operation) {
        case 'initialize':
          sherpa.initBindings();
          final moonshine = message['moonshine_root'] as String;
          recognizer = sherpa.OfflineRecognizer(
            sherpa.OfflineRecognizerConfig(
              model: sherpa.OfflineModelConfig(
                moonshine: sherpa.OfflineMoonshineModelConfig(
                  encoder: '$moonshine\\encoder_model.ort',
                  mergedDecoder: '$moonshine\\decoder_model_merged.ort',
                ),
                tokens: '$moonshine\\tokens.txt',
                numThreads: 2,
                debug: false,
              ),
            ),
          );
          extractor = sherpa.SpeakerEmbeddingExtractor(
            config: sherpa.SpeakerEmbeddingExtractorConfig(
              model: message['speaker_model'] as String,
              numThreads: 2,
              debug: false,
            ),
          );
          final keyword = message['keyword_root'] as String;
          spotter = sherpa.KeywordSpotter(
            sherpa.KeywordSpotterConfig(
              model: sherpa.OnlineModelConfig(
                transducer: sherpa.OnlineTransducerModelConfig(
                  encoder:
                      '$keyword\\encoder-epoch-13-avg-2-chunk-8-left-64.int8.onnx',
                  decoder:
                      '$keyword\\decoder-epoch-13-avg-2-chunk-8-left-64.onnx',
                  joiner:
                      '$keyword\\joiner-epoch-13-avg-2-chunk-8-left-64.int8.onnx',
                ),
                tokens: '$keyword\\tokens.txt',
                numThreads: 1,
                debug: false,
                modelingUnit: 'phone+ppinyin',
              ),
              keywordsFile: message['keyword_file'] as String,
              keywordsScore: 3,
              keywordsThreshold: 0.1,
            ),
          );
          keywordStream = spotter!.createStream();
          break;
        case 'transcribe':
          final stream = recognizer!.createStream();
          stream.acceptWaveform(
            samples: message['samples'] as Float32List,
            sampleRate: 16000,
          );
          recognizer!.decode(stream);
          value = recognizer!.getResult(stream).text;
          stream.free();
          break;
        case 'speaker_embedding':
          final stream = extractor!.createStream();
          stream.acceptWaveform(
            samples: message['samples'] as Float32List,
            sampleRate: 16000,
          );
          if (!extractor!.isReady(stream)) {
            stream.free();
            throw StateError('The voice sample is too short.');
          }
          value = extractor!.compute(stream);
          stream.free();
          break;
        case 'wake_chunk':
          final stream = keywordStream!;
          stream.acceptWaveform(
            samples: message['samples'] as Float32List,
            sampleRate: 16000,
          );
          while (spotter!.isReady(stream)) {
            spotter!.decode(stream);
          }
          final keyword = spotter!.getResult(stream).keyword;
          value = keyword.isNotEmpty;
          if (value == true) spotter!.reset(stream);
          break;
        case 'wake_reset':
          keywordStream?.free();
          keywordStream = spotter!.createStream();
          break;
        case 'dispose':
          keywordStream?.free();
          keywordStream = null;
          spotter?.free();
          spotter = null;
          extractor?.free();
          extractor = null;
          recognizer?.free();
          recognizer = null;
          break;
      }
      responses.send({'id': id, 'ok': true, 'value': value});
      if (operation == 'dispose') commands.close();
    } catch (error) {
      responses.send({
        'id': id,
        'ok': false,
        'code': switch (operation) {
          'transcribe' => 'stt_failed',
          'speaker_embedding' => 'speaker_failed',
          'wake_chunk' || 'wake_reset' => 'wake_failed',
          _ => 'voice_runtime_failed',
        },
        'message': error.toString(),
      });
    }
  });
}
