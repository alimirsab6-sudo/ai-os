import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../../core/result.dart';
import 'microphone_capture.dart';

/// Windows microphone capture backend.
///
/// Uses the free `record` package to capture 16 kHz mono PCM audio.
/// Diagnostic messages are printed to the debug console so we can verify
/// that Windows is actually delivering microphone samples.
final class WindowsMicrophoneCapture implements MicrophoneCapture {
  final AudioRecorder _recorder = AudioRecorder();

  StreamSubscription<Uint8List>? _audioSubscription;
  StreamController<Float32List>? _outputController;

  bool _capturing = false;
  int _packetCount = 0;
  int _sampleCount = 0;

  @override
  bool get isCapturing => _capturing;

  @override
  Future<Result<Stream<Float32List>>> start() async {
    print('[MIC] ========================================');
    print('[MIC] START REQUESTED');

    if (_capturing) {
      print('[MIC] ERROR: already capturing');

      return Result.failure(
        const Failure(
          'Microphone is already capturing.',
          code: 'already_capturing',
        ),
      );
    }

    try {
      print('[MIC] Checking microphone permission...');

      final permission = await _recorder.hasPermission();

      print('[MIC] Permission result: $permission');

      if (!permission) {
        print('[MIC] ERROR: microphone permission denied');

        return Result.failure(
          const Failure(
            'Windows microphone permission was not granted.',
            code: 'microphone_permission_denied',
          ),
        );
      }

      print('[MIC] Creating output stream...');

      final controller = StreamController<Float32List>();

      _outputController = controller;
      _packetCount = 0;
      _sampleCount = 0;

      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      );

      print('[MIC] Configuration:');
      print('[MIC]   encoder = pcm16bits');
      print('[MIC]   sampleRate = 16000');
      print('[MIC]   channels = 1');
      print('[MIC] Starting Windows audio stream...');

      final stream = await _recorder.startStream(config);

      print('[MIC] ========================================');
      print('[MIC] SUCCESS: WINDOWS MICROPHONE STREAM STARTED');
      print('[MIC] Waiting for audio samples...');
      print('[MIC] ========================================');

      _capturing = true;

      _audioSubscription = stream.listen(
        (Uint8List bytes) {
          if (!_capturing || controller.isClosed) {
            return;
          }

          _packetCount++;

          final samples = _pcm16ToFloat32(bytes);

          _sampleCount += samples.length;

          if (_packetCount <= 10 || _packetCount % 50 == 0) {
            print(
              '[MIC] AUDIO RECEIVED '
              'packet=$_packetCount '
              'bytes=${bytes.length} '
              'samples=${samples.length} '
              'totalSamples=$_sampleCount',
            );
          }

          controller.add(samples);
        },
        onError: (Object error, StackTrace stackTrace) {
          print('[MIC] STREAM ERROR: $error');
          print('[MIC] STACK: $stackTrace');

          if (!controller.isClosed) {
            controller.addError(error, stackTrace);
          }
        },
        onDone: () {
          print('[MIC] AUDIO STREAM CLOSED');

          if (!controller.isClosed) {
            unawaited(controller.close());
          }
        },
      );

      return Result.success(controller.stream);
    } catch (error, stackTrace) {
      print('[MIC] ========================================');
      print('[MIC] FAILED TO START MICROPHONE');
      print('[MIC] ERROR: $error');
      print('[MIC] STACK: $stackTrace');
      print('[MIC] ========================================');

      _capturing = false;

      await _audioSubscription?.cancel();
      _audioSubscription = null;

      final controller = _outputController;
      _outputController = null;

      if (controller != null && !controller.isClosed) {
        await controller.close();
      }

      return Result.failure(
        Failure(
          'Unable to start the Windows microphone: $error',
          code: 'microphone_start_failed',
        ),
      );
    }
  }

  Float32List _pcm16ToFloat32(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    final samples = Float32List(sampleCount);

    final data = ByteData.sublistView(bytes);

    for (var i = 0; i < sampleCount; i++) {
      final value = data.getInt16(i * 2, Endian.little);
      samples[i] = value / 32768.0;
    }

    return samples;
  }

  @override
  Future<void> stop() async {
    print('[MIC] STOP REQUESTED');

    _capturing = false;

    await _audioSubscription?.cancel();
    _audioSubscription = null;

    try {
      await _recorder.stop();
    } catch (error) {
      print('[MIC] Stop error: $error');
    }

    final controller = _outputController;
    _outputController = null;

    if (controller != null && !controller.isClosed) {
      await controller.close();
    }

    print('[MIC] STOP COMPLETE');
  }

  @override
  Future<void> dispose() async {
    print('[MIC] DISPOSE');

    await stop();
    await _recorder.dispose();

    print('[MIC] DISPOSE COMPLETE');
  }
}
