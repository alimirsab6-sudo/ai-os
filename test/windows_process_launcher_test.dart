import 'dart:io';

import 'package:ai_os/tools/windows/applications/application_descriptor.dart';
import 'package:ai_os/tools/windows/applications/windows_process_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

ResolvedApplication _application(ApplicationLaunchStrategy strategy) {
  return ResolvedApplication(
    descriptor: ApplicationDescriptor(
      id: strategy.name,
      displayName: 'Approved Test Application',
      resolutionStrategy: ExecutableResolutionStrategy.windowsKnownLocations,
      locations: const [],
      launchStrategy: strategy,
    ),
    executablePath: r'C:\approved\application.exe',
  );
}

void main() {
  test('direct strategy uses only the non-shell process starter', () async {
    var directCalls = 0;
    var shellCalls = 0;
    final launcher = WindowsProcessLauncher(
      directProcessStarter: (path) async {
        directCalls++;
        expect(path, r'C:\approved\application.exe');
        return 42;
      },
      windowsShellStarter: (_) => shellCalls++,
    );

    final result = await launcher.launch(
      _application(ApplicationLaunchStrategy.directProcess),
    );

    expect(result.isSuccess, isTrue);
    expect(result.fold((receipt) => receipt.processId, (_) => null), 42);
    expect(directCalls, 1);
    expect(shellCalls, 0);
  });

  test(
    'shell strategy uses only the fixed Windows executable starter',
    () async {
      var directCalls = 0;
      var shellCalls = 0;
      final launcher = WindowsProcessLauncher(
        directProcessStarter: (_) async {
          directCalls++;
          return 42;
        },
        windowsShellStarter: (path) {
          shellCalls++;
          expect(path, r'C:\approved\application.exe');
        },
      );

      final result = await launcher.launch(
        _application(ApplicationLaunchStrategy.windowsRunAs),
      );

      expect(result.isSuccess, isTrue);
      expect(result.fold((receipt) => receipt.processId, (_) => 1), isNull);
      expect(directCalls, 0);
      expect(shellCalls, 1);
    },
  );

  test('Windows shell rejection returns a structured launch failure', () async {
    final launcher = WindowsProcessLauncher(
      windowsShellStarter: (path) =>
          throw ProcessException(path, const [], 'rejected', 5),
    );

    final result = await launcher.launch(
      _application(ApplicationLaunchStrategy.windowsRunAs),
    );

    expect(result.isFailure, isTrue);
    expect(
      result.fold((_) => null, (failure) => failure.code),
      'launch_failed',
    );
  });
}
