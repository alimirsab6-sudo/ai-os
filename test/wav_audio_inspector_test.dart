import 'dart:io';
import 'dart:typed_data';

import 'package:ai_os/core/result.dart';
import 'package:ai_os/voice/audio/wav_audio_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('cronyx-wav-');
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('reads 24 kHz mono IEEE float WAV and detects audio samples', () async {
    final file = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}voice.wav',
    );
    await file.writeAsBytes(_floatWav([0, 0.25, -0.5, 0]));

    final result = await const WavAudioInspector().inspect(file.path);

    expect(result, isA<Success<WavAudioMetadata>>());
    final metadata = (result as Success<WavAudioMetadata>).value;
    expect(metadata.formatTag, 3);
    expect(metadata.sampleRate, 24000);
    expect(metadata.channels, 1);
    expect(metadata.bitsPerSample, 32);
    expect(metadata.sampleCount, 4);
    expect(metadata.nonZeroSampleCount, 2);
    expect(metadata.containsAudio, isTrue);
  });

  test('reports missing audio instead of proceeding to playback', () async {
    final result = await const WavAudioInspector().inspect(
      '${temporaryDirectory.path}${Platform.pathSeparator}missing.wav',
    );

    expect(result, isA<Failed<WavAudioMetadata>>());
    expect(
      (result as Failed<WavAudioMetadata>).failure.code,
      'audio_file_missing',
    );
  });

  test('distinguishes a valid but silent WAV from generated speech', () async {
    final file = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}silent.wav',
    );
    await file.writeAsBytes(_floatWav([0, 0, 0, 0]));

    final result = await const WavAudioInspector().inspect(file.path);

    final metadata = (result as Success<WavAudioMetadata>).value;
    expect(metadata.nonZeroSampleCount, 0);
    expect(metadata.containsAudio, isFalse);
  });
}

Uint8List _floatWav(List<double> samples) {
  final dataLength = samples.length * 4;
  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(bytes);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      bytes[offset + index] = value.codeUnitAt(index);
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 3, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 24000, Endian.little);
  data.setUint32(28, 96000, Endian.little);
  data.setUint16(32, 4, Endian.little);
  data.setUint16(34, 32, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, dataLength, Endian.little);
  for (var index = 0; index < samples.length; index++) {
    data.setFloat32(44 + index * 4, samples[index], Endian.little);
  }
  return bytes;
}
