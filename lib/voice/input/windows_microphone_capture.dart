import 'dart:typed_data';
import '../../core/result.dart';
import 'microphone_capture.dart';

final class WindowsMicrophoneCapture implements MicrophoneCapture {
  bool _capturing = false;

  @override
  bool get isCapturing => _capturing;

  @override
  Future<Result<Stream<Float32List>>> start() async {
    if (_capturing) {
      return Result.failure(
        const Failure('Microphone is already capturing.', code: 'already_capturing'),
      );
    }

    return Result.failure(
      const Failure(
        'Windows microphone capture backend is not configured yet.',
        code: 'microphone_backend_unavailable',
      ),
    );
  }

  @override
  Future<void> stop() async {
    _capturing = false;
  }

  @override
  Future<void> dispose() async {
    _capturing = false;
  }
}
