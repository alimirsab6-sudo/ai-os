import '../../core/result.dart';
import 'chrome_profile.dart';

final class ChromeProfileLaunchReceipt {
  const ChromeProfileLaunchReceipt({
    required this.profile,
    required this.processId,
  });

  final ChromeProfile profile;
  final int processId;
}

abstract interface class ChromeLauncher {
  Future<Result<ChromeProfileLaunchReceipt>> launch(String profileId);
}
