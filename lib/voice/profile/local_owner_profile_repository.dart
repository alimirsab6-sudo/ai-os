import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/result.dart';
import 'owner_profile_repository.dart';
import 'owner_voice_profile.dart';

final class LocalOwnerProfileRepository implements OwnerProfileRepository {
  LocalOwnerProfileRepository({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file() async {
    final root = await _directory();
    return File('${root.path}\\CronyX\\voice\\owner_profile.json');
  }

  @override
  Future<Result<OwnerVoiceProfile?>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const Result.success(null);
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, Object?>) throw const FormatException();
      final profile = OwnerVoiceProfile.fromJson(value);
      if (profile.displayName.isEmpty || profile.embedding.length != 256) {
        throw const FormatException();
      }
      return Result.success(profile);
    } catch (_) {
      return const Result.failure(
        Failure('The owner voice profile is invalid.', code: 'profile_invalid'),
      );
    }
  }

  @override
  Future<Result<void>> save(OwnerVoiceProfile profile) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(profile.toJson()), flush: true);
      await temporary.rename(file.path);
      return const Result.success(null);
    } catch (_) {
      return const Result.failure(
        Failure(
          'The owner profile could not be saved.',
          code: 'profile_save_failed',
        ),
      );
    }
  }

  @override
  Future<Result<void>> reset() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
      return const Result.success(null);
    } catch (_) {
      return const Result.failure(
        Failure(
          'The owner profile could not be reset.',
          code: 'profile_reset_failed',
        ),
      );
    }
  }

  @override
  Future<String> storageLocation() async => (await _file()).path;
}
