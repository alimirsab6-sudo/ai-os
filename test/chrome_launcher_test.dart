import 'package:ai_os/browser/chrome/windows_chrome_launcher.dart';
import 'package:ai_os/core/result.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chrome_fakes.dart';

void main() {
  test(
    'launches only the internally resolved executable and profile argument',
    () async {
      final profiles = MockChromeProfileRegistry()..discovered = true;
      String? executable;
      List<String>? arguments;
      final launcher = WindowsChromeLauncher(
        profiles: profiles,
        installationResolver: MockChromeInstallationResolver(),
        processStarter: (path, args) async {
          executable = path;
          arguments = args;
          return 55;
        },
      );
      final result = await launcher.launch(testChromeProfile.id);
      expect(result.isSuccess, isTrue);
      expect(executable, endsWith(r'\chrome.exe'));
      expect(arguments, ['--profile-directory=Profile 1']);
    },
  );

  test(
    'unknown profile is rejected before installation or process launch',
    () async {
      final resolver = MockChromeInstallationResolver();
      var starts = 0;
      final launcher = WindowsChromeLauncher(
        profiles: MockChromeProfileRegistry(),
        installationResolver: resolver,
        processStarter: (_, _) async {
          starts++;
          return 1;
        },
      );
      final result = await launcher.launch('chrome_profile_ffffffffffffffff');
      expect(_failureCode(result), 'unknown_chrome_profile');
      expect(resolver.resolveCount, 0);
      expect(starts, 0);
    },
  );

  test('invalid executable resolution prevents process launch', () async {
    final profiles = MockChromeProfileRegistry()..discovered = true;
    var starts = 0;
    final launcher = WindowsChromeLauncher(
      profiles: profiles,
      installationResolver: MockChromeInstallationResolver(
        failure: const Failure('invalid', code: 'invalid_chrome_installation'),
      ),
      processStarter: (_, _) async {
        starts++;
        return 1;
      },
    );
    expect(
      _failureCode(await launcher.launch(testChromeProfile.id)),
      'invalid_chrome_installation',
    );
    expect(starts, 0);
  });

  test('process failure is sanitized', () async {
    final profiles = MockChromeProfileRegistry()..discovered = true;
    final launcher = WindowsChromeLauncher(
      profiles: profiles,
      installationResolver: MockChromeInstallationResolver(),
      processStarter: (_, _) async => throw StateError('private path'),
    );
    final result = await launcher.launch(testChromeProfile.id);
    expect(_failureCode(result), 'chrome_launch_failed');
    expect(
      result.fold((_) => '', (failure) => failure.message),
      isNot(contains('private path')),
    );
  });
}

String? _failureCode<T>(Result<T> result) =>
    result.fold((_) => null, (failure) => failure.code);

