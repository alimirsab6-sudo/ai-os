import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

void main(List<String> arguments) {
  final root = Directory.current.path;
  final pubCache = Platform.environment['LOCALAPPDATA'];
  if (pubCache == null) {
    throw StateError('LOCALAPPDATA is unavailable.');
  }
  final nativeRoot =
      '$pubCache\\Pub\\Cache\\hosted\\pub.dev'
      '\\sherpa_onnx_windows-1.13.6\\windows';
  DynamicLibrary.open('$nativeRoot\\onnxruntime.dll');
  sherpa.initBindings(nativeRoot);

  final moonshine =
      '$root\\runtime\\voice\\models'
      '\\sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27';
  final recognizer = sherpa.OfflineRecognizer(
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
  final wave = sherpa.readWave(
    arguments.isEmpty ? '$moonshine\\test_wavs\\0.wav' : arguments.first,
  );
  final asrStream = recognizer.createStream();
  asrStream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
  recognizer.decode(asrStream);
  final transcript = recognizer.getResult(asrStream).text.trim();
  asrStream.free();
  recognizer.free();
  if (transcript.isEmpty) throw StateError('STT returned an empty transcript.');
  stdout.writeln('STT: $transcript');

  final extractor = sherpa.SpeakerEmbeddingExtractor(
    config: sherpa.SpeakerEmbeddingExtractorConfig(
      model:
          '$root\\runtime\\voice\\models'
          '\\wespeaker_en_voxceleb_resnet34.onnx',
      numThreads: 2,
      debug: false,
    ),
  );
  final speakerStream = extractor.createStream();
  speakerStream.acceptWaveform(
    samples: wave.samples,
    sampleRate: wave.sampleRate,
  );
  if (!extractor.isReady(speakerStream)) {
    throw StateError('Speaker sample is too short for embedding extraction.');
  }
  final embedding = extractor.compute(speakerStream);
  speakerStream.free();
  extractor.free();
  if (embedding.isEmpty) throw StateError('Speaker embedding is empty.');
  stdout.writeln('SPEAKER_EMBEDDING_DIM: ${embedding.length}');

  final kws =
      '$root\\runtime\\voice\\models'
      '\\sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20';
  final spotter = sherpa.KeywordSpotter(
    sherpa.KeywordSpotterConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: '$kws\\encoder-epoch-13-avg-2-chunk-8-left-64.int8.onnx',
          decoder: '$kws\\decoder-epoch-13-avg-2-chunk-8-left-64.onnx',
          joiner: '$kws\\joiner-epoch-13-avg-2-chunk-8-left-64.int8.onnx',
        ),
        tokens: '$kws\\tokens.txt',
        numThreads: 1,
        debug: false,
        modelingUnit: 'phone+ppinyin',
      ),
      keywordsFile: '$root\\runtime\\voice\\config\\keywords.txt',
      keywordsScore: 3,
      keywordsThreshold: 0.1,
    ),
  );
  final keywordStream = spotter.createStream();
  if (arguments.isNotEmpty) {
    final keywordWave = sherpa.readWave(arguments.first);
    var keyword = '';
    void feed(Float32List samples) {
      final chunkSize = keywordWave.sampleRate ~/ 10;
      for (var offset = 0; offset < samples.length; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, samples.length);
        keywordStream.acceptWaveform(
          samples: Float32List.sublistView(samples, offset, end),
          sampleRate: keywordWave.sampleRate,
        );
        while (spotter.isReady(keywordStream)) {
          spotter.decode(keywordStream);
        }
        final detected = spotter.getResult(keywordStream).keyword;
        if (detected.isNotEmpty) keyword = detected;
      }
    }

    feed(keywordWave.samples);
    feed(Float32List(keywordWave.sampleRate));
    keywordStream.inputFinished();
    while (spotter.isReady(keywordStream)) {
      spotter.decode(keywordStream);
    }
    final finalKeyword = spotter.getResult(keywordStream).keyword;
    if (finalKeyword.isNotEmpty) keyword = finalKeyword;
    final expectNone = arguments.contains('--expect-none');
    if (expectNone && keyword.isNotEmpty) {
      throw StateError('Unexpected wake result "$keyword".');
    }
    if (!expectNone && keyword != 'CRONY') {
      throw StateError('Expected CRONY wake result, received "$keyword".');
    }
    stdout.writeln(
      expectNone
          ? 'WAKE_REJECTED: unrelated speech'
          : 'WAKE_DETECTED: $keyword',
    );
  }
  keywordStream.free();
  spotter.free();
  stdout.writeln('WAKE_SPOTTER: ready');
}
