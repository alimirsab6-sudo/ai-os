import 'package:ai_os/browser/chrome/chrome_installation_resolver.dart';
import 'package:ai_os/browser/chrome/chrome_launcher.dart';
import 'package:ai_os/browser/chrome/chrome_profile.dart';
import 'package:ai_os/browser/chrome/chrome_profile_registry.dart';
import 'package:ai_os/core/result.dart';

const testChromeProfile = ChromeProfile(
  id: 'chrome_profile_0123456789abcdef',
  displayName: 'Work',
  directoryIdentifier: 'Profile 1',
  isDefault: false,
);

final class MockChromeInstallationResolver
    implements ChromeInstallationResolver {
  MockChromeInstallationResolver({this.failure});
  final Failure? failure;
  int resolveCount = 0;

  @override
  Result<ResolvedChromeInstallation> resolve() {
    resolveCount++;
    if (failure case final failure?) return Result.failure(failure);
    return const Result.success(
      ResolvedChromeInstallation(
        executablePath:
            r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      ),
    );
  }
}

final class MockChromeProfileRegistry implements ChromeProfileRegistry {
  MockChromeProfileRegistry({
    this.profiles = const [testChromeProfile],
    this.discoveryFailure,
  });

  final List<ChromeProfile> profiles;
  final Failure? discoveryFailure;
  bool discovered = false;
  int discoveryCount = 0;

  @override
  Future<Result<List<ChromeProfile>>> discoverProfiles() async {
    discoveryCount++;
    if (discoveryFailure case final failure?) return Result.failure(failure);
    discovered = true;
    return Result.success(profiles);
  }

  @override
  Result<ChromeProfile> getProfile(String profileId) => resolveProfile(
    profileId,
  ).fold((resolved) => Result.success(resolved.profile), Result.failure);

  @override
  List<ChromeProfile> listProfiles() => discovered ? profiles : const [];

  @override
  Result<ResolvedChromeProfile> resolveProfile(String profileId) {
    for (final profile in listProfiles()) {
      if (profile.id == profileId) {
        return Result.success(ResolvedChromeProfile(profile: profile));
      }
    }
    return const Result.failure(
      Failure('Unknown Chrome profile.', code: 'unknown_chrome_profile'),
    );
  }
}

final class MockChromeLauncher implements ChromeLauncher {
  MockChromeLauncher({this.failure, this.profile = testChromeProfile});

  final Failure? failure;
  final ChromeProfile profile;
  int launchCount = 0;
  String? profileId;

  @override
  Future<Result<ChromeProfileLaunchReceipt>> launch(String profileId) async {
    launchCount++;
    this.profileId = profileId;
    if (failure case final failure?) return Result.failure(failure);
    return Result.success(
      ChromeProfileLaunchReceipt(profile: profile, processId: 4321),
    );
  }
}

