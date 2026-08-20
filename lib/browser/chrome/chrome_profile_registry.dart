import '../../core/result.dart';
import 'chrome_profile.dart';

abstract interface class ChromeProfileRegistry {
  Future<Result<List<ChromeProfile>>> discoverProfiles();
  Result<ChromeProfile> getProfile(String profileId);
  List<ChromeProfile> listProfiles();
  Result<ResolvedChromeProfile> resolveProfile(String profileId);
}

