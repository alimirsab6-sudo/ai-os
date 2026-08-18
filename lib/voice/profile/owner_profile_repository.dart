import '../../core/result.dart';
import 'owner_voice_profile.dart';

abstract interface class OwnerProfileRepository {
  Future<Result<OwnerVoiceProfile?>> load();

  Future<Result<void>> save(OwnerVoiceProfile profile);

  Future<Result<void>> reset();

  Future<String> storageLocation();
}
