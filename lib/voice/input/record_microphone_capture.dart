import 'dart:typed_data';

import 'package:record/record.dart';

import '../../core/result.dart';
import 'microphone_capture.dart';

final class RecordMicrophoneCapture implements MicrophoneCapture {
  RecordMicrophoneCapture({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  static const sampleRate = 16000;
  final AudioRecorder _recorder;
  bool _capturing = false;

  @override
  bool get isCapturing => _capturing;

  @override
  Future<Result<Stream<Float32List>>> start() async {
    if (_capturing) {
      return const Result.failure(
        Failure('The microphone is already active.', code: 'microphone_busy'),
      );
    }
    try {
      if (!await _recorder.hasPermission()) {
        return const Result.failure(
          Failure(
            'Microphone permission was denied.',
            code: 'microphone_permission_denied',
          ),
        );
      }
      final bytes = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );
      _capturing = true;
      return Result.success(bytes.map(_pcm16ToFloat));
    } catch (_) {
      _capturing = false;
      return const Result.failure(
        Failure(
          'The microphone could not be started.',
          code: 'microphone_failed',
        ),
      );
    }
  }

  Float32List _pcm16ToFloat(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    final values = Float32List(sampleCount);
    final data = ByteData.sublistView(bytes);
    for (var index = 0; index < sampleCount; index++) {
      values[index] = data.getInt16(index * 2, Endian.little) / 32768.0;
    }
    return values;
  }

  @override
  Future<void> stop() async {
    if (!_capturing) return;
    _capturing = false;
    try {
      await _recorder.stop();
    } catch (_) {
      // Cleanup is best-effort; the next start still performs a real check.
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}
