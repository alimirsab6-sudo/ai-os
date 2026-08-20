import 'dart:typed_data';
import 'dart:async';

import 'package:ai_os/core/result.dart';
import 'package:ai_os/voice/input/microphone_capture.dart';
import 'package:ai_os/voice/profile/owner_profile_repository.dart';
import 'package:ai_os/voice/profile/owner_voice_profile.dart';
import 'package:ai_os/voice/recognition/local_voice_runtime.dart';

final class FakeMicrophoneCapture implements MicrophoneCapture {
  final List<List<Float32List>> recordings = [];
  Failure? startFailure;
  int startCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  bool _capturing = false;
  StreamController<Float32List>? _controller;

  @override
  bool get isCapturing => _capturing;

  Future<void> closeActiveStreamUnexpectedly() async {
    final controller = _controller;
    _controller = null;
    _capturing = false;
    await controller?.close();
  }

  @override
  Future<Result<Stream<Float32List>>> start() async {
    startCount++;
    final failure = startFailure;
    if (failure != null) return Result.failure(failure);
    _capturing = true;
    final chunks = recordings.isEmpty
        ? <Float32List>[]
        : recordings.removeAt(0);
    late final StreamController<Float32List> controller;
    controller = StreamController<Float32List>(
      onListen: () {
        for (final chunk in chunks) {
          controller.add(chunk);
        }
      },
    );
    _controller = controller;
    return Result.success(controller.stream);
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _capturing = false;
    final controller = _controller;
    if (controller != null) {
      if (controller.hasListener) {
        await controller.close();
      } else {
        unawaited(controller.close());
      }
    }
    _controller = null;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    _capturing = false;
    final controller = _controller;
    if (controller != null) {
      if (controller.hasListener) {
        await controller.close();
      } else {
        unawaited(controller.close());
      }
    }
    _controller = null;
  }
}

final class FakeLocalVoiceRuntime implements LocalVoiceRuntime {
  Result<void> initializeResult = const Result.success(null);
  final List<Result<String>> transcripts = [];
  final List<Result<Float32List>> embeddings = [];
  final List<Result<bool>> wakeResults = [];
  int initializeCount = 0;
  int transcribeCount = 0;
  int embeddingCount = 0;
  int wakeCount = 0;
  int resetWakeCount = 0;
  int disposeCount = 0;

  @override
  Future<Result<void>> initialize() async {
    initializeCount++;
    return initializeResult;
  }

  @override
  Future<Result<String>> transcribe(Float32List samples) async {
    transcribeCount++;
    return transcripts.isEmpty
        ? const Result.success('')
        : transcripts.removeAt(0);
  }

  @override
  Future<Result<Float32List>> createSpeakerEmbedding(
    Float32List samples,
  ) async {
    embeddingCount++;
    return embeddings.isEmpty
        ? Result.success(unitEmbedding())
        : embeddings.removeAt(0);
  }

  @override
  Future<Result<bool>> detectWakePhrase(Float32List samples) async {
    wakeCount++;
    return wakeResults.isEmpty
        ? const Result.success(false)
        : wakeResults.removeAt(0);
  }

  @override
  Future<Result<void>> resetWakePhrase() async {
    resetWakeCount++;
    return const Result.success(null);
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

final class MemoryOwnerProfileRepository implements OwnerProfileRepository {
  MemoryOwnerProfileRepository([this.profile]);

  OwnerVoiceProfile? profile;
  Failure? loadFailure;
  Failure? saveFailure;
  int saveCount = 0;
  int resetCount = 0;

  @override
  Future<Result<OwnerVoiceProfile?>> load() async {
    final failure = loadFailure;
    return failure == null ? Result.success(profile) : Result.failure(failure);
  }

  @override
  Future<Result<void>> save(OwnerVoiceProfile value) async {
    saveCount++;
    final failure = saveFailure;
    if (failure != null) return Result.failure(failure);
    profile = value;
    return const Result.success(null);
  }

  @override
  Future<Result<void>> reset() async {
    resetCount++;
    profile = null;
    return const Result.success(null);
  }

  @override
  Future<String> storageLocation() async =>
      r'C:\Users\test\CronyX\voice\owner_profile.json';
}

Float32List unitEmbedding([int axis = 0]) {
  final value = Float32List(256);
  value[axis] = 1;
  return value;
}

List<Float32List> utterance() => [
  Float32List.fromList(List<double>.filled(16000, .1)),
  Float32List(16000),
];

OwnerVoiceProfile ownerProfile({String name = 'Ali'}) => OwnerVoiceProfile(
  displayName: name,
  embedding: unitEmbedding(),
  createdAt: DateTime.utc(2026, 8, 18),
);

