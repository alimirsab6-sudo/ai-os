import '../core/result.dart';
import 'chrome/chrome_profile.dart';

final class BrowserSession {
  ChromeProfile? _selectedProfile;

  ChromeProfile? get selectedProfile => _selectedProfile;

  Result<void> selectProfile(ChromeProfile profile) {
    if (!RegExp(r'^chrome_profile_[0-9a-f]{16}$').hasMatch(profile.id) ||
        profile.displayName.trim().isEmpty ||
        profile.directoryIdentifier.trim().isEmpty) {
      return const Result.failure(
        Failure(
          'Invalid browser profile state.',
          code: 'invalid_profile_state',
        ),
      );
    }
    _selectedProfile = profile;
    return const Result.success(null);
  }

  void clear() => _selectedProfile = null;
}

