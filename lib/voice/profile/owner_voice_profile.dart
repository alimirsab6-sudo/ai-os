import 'dart:typed_data';

final class OwnerVoiceProfile {
  const OwnerVoiceProfile({
    required this.displayName,
    required this.embedding,
    required this.createdAt,
    this.modelId = 'wespeaker_en_voxceleb_resnet34',
    this.version = 1,
  });

  final String displayName;
  final Float32List embedding;
  final DateTime createdAt;
  final String modelId;
  final int version;

  Map<String, Object?> toJson() => {
    'version': version,
    'display_name': displayName,
    'model_id': modelId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'embedding': embedding.toList(growable: false),
  };

  static OwnerVoiceProfile fromJson(Map<String, Object?> json) {
    final values = json['embedding'];
    if (values is! List || values.isEmpty) {
      throw const FormatException('Missing speaker embedding.');
    }
    return OwnerVoiceProfile(
      displayName: (json['display_name'] as String).trim(),
      embedding: Float32List.fromList(
        values.map((value) => (value as num).toDouble()).toList(),
      ),
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      modelId: json['model_id'] as String,
      version: json['version'] as int,
    );
  }
}
