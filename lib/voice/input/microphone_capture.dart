import 'dart:typed_data';

import '../../core/result.dart';

abstract interface class MicrophoneCapture {
  bool get isCapturing;

  Future<Result<Stream<Float32List>>> start();

  Future<void> stop();

  Future<void> dispose();
}
