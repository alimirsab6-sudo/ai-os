import 'dart:io';

import '../../core/result.dart';
import 'chrome_installation_resolver.dart';
import 'chrome_launcher.dart';
import 'chrome_profile_registry.dart';

typedef ChromeProcessStarter =
    Future<int> Function(String executablePath, List<String> arguments);

Future<int> _startChrome(String executablePath, List<String> arguments) async {
  final process = await Process.start(
    executablePath,
    arguments,
    mode: ProcessStartMode.detached,
    runInShell: false,
  );
  return process.pid;
}

final class WindowsChromeLauncher implements ChromeLauncher {
  WindowsChromeLauncher({
    required this.profiles,
    required this.installationResolver,
    ChromeProcessStarter? processStarter,
  }) : _processStarter = processStarter ?? _startChrome,
       _usesNativeStarter = processStarter == null;

  final ChromeProfileRegistry profiles;
  final ChromeInstallationResolver installationResolver;
  final ChromeProcessStarter _processStarter;
  final bool _usesNativeStarter;

  @override
  Future<Result<ChromeProfileLaunchReceipt>> launch(String profileId) async {
    if (!Platform.isWindows && _usesNativeStarter) {
      return const Result.failure(
        Failure(
          'Chrome profile launching is supported only on Windows.',
          code: 'unsupported_platform',
        ),
      );
    }
    final profileResult = profiles.resolveProfile(profileId);
    if (profileResult case Failed(:final failure)) {
      return Result.failure(failure);
    }
    final installationResult = installationResolver.resolve();
    if (installationResult case Failed(:final failure)) {
      return Result.failure(failure);
    }
    final profile = (profileResult as Success).value;
    final installation = (installationResult as Success).value;
    try {
      final processId = await _processStarter(installation.executablePath, [
        '--profile-directory=${profile.directoryIdentifier}',
      ]);
      return Result.success(
        ChromeProfileLaunchReceipt(
          profile: profile.profile,
          processId: processId,
        ),
      );
    } on ProcessException {
      return const Result.failure(
        Failure('Chrome profile launch failed.', code: 'chrome_launch_failed'),
      );
    } on FileSystemException {
      return const Result.failure(
        Failure('Chrome profile launch failed.', code: 'chrome_launch_failed'),
      );
    } on Object {
      return const Result.failure(
        Failure('Chrome profile launch failed.', code: 'chrome_launch_failed'),
      );
    }
  }
}
