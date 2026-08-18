import '../../core/result.dart';

final class KokoroBridgeRequest {
  const KokoroBridgeRequest({
    required this.id,
    required this.text,
    this.createdAtEpochMicroseconds = 0,
  });

  static const int maxTextLength = 2000;

  final String id;
  final String text;
  final int createdAtEpochMicroseconds;

  Map<String, Object> toJson() => {
    'id': id,
    'operation': 'synthesize',
    'text': text,
  };

  static Result<KokoroBridgeRequest> fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final operation = json['operation'];
    final text = json['text'];
    if (id is! String || !RegExp(r'^\d{1,18}$').hasMatch(id)) {
      return const Result.failure(
        Failure('The bridge request id is invalid.', code: 'invalid_request'),
      );
    }
    if (operation != 'synthesize') {
      return const Result.failure(
        Failure('The bridge operation is invalid.', code: 'invalid_request'),
      );
    }
    if (text is! String || text.trim().isEmpty || text.length > maxTextLength) {
      return const Result.failure(
        Failure('The speech text is invalid.', code: 'invalid_request'),
      );
    }
    return Result.success(KokoroBridgeRequest(id: id, text: text.trim()));
  }
}

final class KokoroAudioArtifact {
  const KokoroAudioArtifact({
    required this.filePath,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    this.formatTag = 3,
    this.fileSize = 0,
    this.nonZeroSampleCount = 0,
    this.nodeQueueMilliseconds = 0,
    this.inferenceMilliseconds = 0,
    this.wavWriteMilliseconds = 0,
    this.nodeTotalMilliseconds = 0,
    this.flutterReceivedAtEpochMicroseconds = 0,
    this.cacheHit = false,
  });

  final String filePath;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int formatTag;
  final int fileSize;
  final int nonZeroSampleCount;
  final double nodeQueueMilliseconds;
  final double inferenceMilliseconds;
  final double wavWriteMilliseconds;
  final double nodeTotalMilliseconds;
  final int flutterReceivedAtEpochMicroseconds;
  final bool cacheHit;
}

abstract interface class KokoroBridge {
  Future<Result<void>> initialize();

  Future<Result<KokoroAudioArtifact>> synthesize(KokoroBridgeRequest request);

  Future<void> dispose();
}
