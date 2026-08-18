import 'dart:typed_data';

import '../../core/result.dart';

abstract interface class LocalVoiceRuntime {
  Future<Result<void>> initialize();

  Future<Result<String>> transcribe(Float32List samples);

  Future<Result<Float32List>> createSpeakerEmbedding(Float32List samples);

  Future<Result<bool>> detectWakePhrase(Float32List samples);

  Future<Result<void>> resetWakePhrase();

  Future<void> dispose();
}

final class VoiceRuntimePaths {
  const VoiceRuntimePaths({required this.projectRoot});

  final String projectRoot;

  String get modelRoot => '$projectRoot\\runtime\\voice\\models';
  String get moonshineRoot =>
      '$modelRoot\\sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27';
  String get keywordRoot =>
      '$modelRoot\\sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20';
  String get speakerModel => '$modelRoot\\wespeaker_en_voxceleb_resnet34.onnx';
  String get keywordFile =>
      '$projectRoot\\runtime\\voice\\config\\keywords.txt';

  List<String> get requiredFiles => [
    '$moonshineRoot\\encoder_model.ort',
    '$moonshineRoot\\decoder_model_merged.ort',
    '$moonshineRoot\\tokens.txt',
    '$keywordRoot\\encoder-epoch-13-avg-2-chunk-8-left-64.int8.onnx',
    '$keywordRoot\\decoder-epoch-13-avg-2-chunk-8-left-64.onnx',
    '$keywordRoot\\joiner-epoch-13-avg-2-chunk-8-left-64.int8.onnx',
    '$keywordRoot\\tokens.txt',
    speakerModel,
    keywordFile,
  ];
}
