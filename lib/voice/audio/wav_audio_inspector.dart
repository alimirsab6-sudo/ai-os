import 'dart:io';
import 'dart:typed_data';

import '../../core/result.dart';

final class WavAudioMetadata {
  const WavAudioMetadata({
    required this.fileSize,
    required this.formatTag,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.sampleCount,
    required this.nonZeroSampleCount,
  });

  final int fileSize;
  final int formatTag;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int sampleCount;
  final int nonZeroSampleCount;

  bool get containsAudio => nonZeroSampleCount > 0;
}

/// Reads the RIFF chunks instead of assuming a fixed 44-byte WAV header.
final class WavAudioInspector {
  const WavAudioInspector();

  Future<Result<WavAudioMetadata>> inspect(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return const Result.failure(
        Failure('Speech audio file is missing.', code: 'audio_file_missing'),
      );
    }
    late final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return const Result.failure(
        Failure(
          'Speech audio file could not be read.',
          code: 'audio_read_failed',
        ),
      );
    }
    if (bytes.length < 44) {
      return const Result.failure(
        Failure('Speech audio file is empty.', code: 'audio_file_empty'),
      );
    }

    try {
      final data = ByteData.sublistView(bytes);
      if (_ascii(bytes, 0, 4) != 'RIFF' || _ascii(bytes, 8, 4) != 'WAVE') {
        return _invalidFormat();
      }
      int? formatTag;
      int? channels;
      int? sampleRate;
      int? bitsPerSample;
      int? audioOffset;
      int? audioLength;
      var offset = 12;
      while (offset + 8 <= bytes.length) {
        final chunkId = _ascii(bytes, offset, 4);
        final chunkLength = data.getUint32(offset + 4, Endian.little);
        final chunkStart = offset + 8;
        if (chunkStart + chunkLength > bytes.length) return _invalidFormat();
        if (chunkId == 'fmt ' && chunkLength >= 16) {
          formatTag = data.getUint16(chunkStart, Endian.little);
          channels = data.getUint16(chunkStart + 2, Endian.little);
          sampleRate = data.getUint32(chunkStart + 4, Endian.little);
          bitsPerSample = data.getUint16(chunkStart + 14, Endian.little);
        } else if (chunkId == 'data') {
          audioOffset = chunkStart;
          audioLength = chunkLength;
        }
        offset = chunkStart + chunkLength + (chunkLength.isOdd ? 1 : 0);
      }
      if (formatTag == null ||
          channels == null ||
          sampleRate == null ||
          bitsPerSample == null ||
          audioOffset == null ||
          audioLength == null) {
        return _invalidFormat();
      }

      final bytesPerSample = bitsPerSample ~/ 8;
      if (bytesPerSample <= 0 || audioLength % bytesPerSample != 0) {
        return _invalidFormat();
      }
      var nonZeroSamples = 0;
      final sampleCount = audioLength ~/ bytesPerSample;
      if (formatTag == 3 && bitsPerSample == 32) {
        for (
          var index = audioOffset;
          index < audioOffset + audioLength;
          index += 4
        ) {
          if (data.getFloat32(index, Endian.little) != 0) nonZeroSamples++;
        }
      } else if (formatTag == 1 && bitsPerSample == 16) {
        for (
          var index = audioOffset;
          index < audioOffset + audioLength;
          index += 2
        ) {
          if (data.getInt16(index, Endian.little) != 0) nonZeroSamples++;
        }
      } else {
        return _invalidFormat();
      }

      return Result.success(
        WavAudioMetadata(
          fileSize: bytes.length,
          formatTag: formatTag,
          sampleRate: sampleRate,
          channels: channels,
          bitsPerSample: bitsPerSample,
          sampleCount: sampleCount,
          nonZeroSampleCount: nonZeroSamples,
        ),
      );
    } on RangeError {
      return _invalidFormat();
    } on FormatException {
      return _invalidFormat();
    }
  }

  String _ascii(Uint8List bytes, int offset, int length) =>
      String.fromCharCodes(bytes.sublist(offset, offset + length));

  Result<WavAudioMetadata> _invalidFormat() => const Result.failure(
    Failure('Speech audio has an invalid WAV format.', code: 'invalid_wav'),
  );
}
