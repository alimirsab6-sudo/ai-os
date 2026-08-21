import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

final class CronyxIdentityProfile {
  const CronyxIdentityProfile({
    required this.name,
    required this.pinHash,
    required this.embedding,
  });

  final String name;
  final String pinHash;
  final List<double> embedding;

  Map<String, Object> toJson() => {
    'version': 1,
    'name': name,
    'pinHash': pinHash,
    'embedding': embedding,
  };

  static CronyxIdentityProfile? fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final pinHash = json['pinHash'];
    final rawEmbedding = json['embedding'];

    if (name is! String ||
        name.trim().isEmpty ||
        pinHash is! String ||
        rawEmbedding is! List) {
      return null;
    }

    final embedding = <double>[];

    for (final value in rawEmbedding) {
      if (value is! num) return null;
      embedding.add(value.toDouble());
    }

    if (embedding.isEmpty) return null;

    return CronyxIdentityProfile(
      name: name.trim(),
      pinHash: pinHash,
      embedding: embedding,
    );
  }
}

final class CronyxIdentityStore {
  Future<File> _file() async {
    final root = await getApplicationSupportDirectory();

    return File(
      '${root.path}${Platform.pathSeparator}'
      'CronyX${Platform.pathSeparator}'
      'identity${Platform.pathSeparator}'
      'profile.json',
    );
  }

  Future<CronyxIdentityProfile?> load() async {
    try {
      final file = await _file();

      if (!await file.exists()) return null;

      final decoded = jsonDecode(await file.readAsString());

      if (decoded is! Map) return null;

      return CronyxIdentityProfile.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required String name,
    required String pin,
    required List<double> embedding,
  }) async {
    final file = await _file();

    await file.parent.create(recursive: true);

    final profile = CronyxIdentityProfile(
      name: name.trim(),
      pinHash: _hashPin(pin),
      embedding: List<double>.from(embedding),
    );

    final temporary = File('${file.path}.tmp');

    await temporary.writeAsString(jsonEncode(profile.toJson()), flush: true);

    await temporary.rename(file.path);
  }

  Future<bool> verifyPin(CronyxIdentityProfile profile, String pin) async {
    return profile.pinHash == _hashPin(pin);
  }

  Future<void> reset() async {
    final file = await _file();

    if (await file.exists()) {
      await file.delete();
    }
  }

  String _hashPin(String pin) {
    return sha256.convert(utf8.encode(pin)).toString();
  }
}
