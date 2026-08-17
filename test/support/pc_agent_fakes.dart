import 'package:ai_os/core/result.dart';
import 'package:ai_os/tools/windows/applications/application_descriptor.dart';
import 'package:ai_os/tools/windows/applications/application_launcher.dart';
import 'package:ai_os/tools/windows/applications/windows_application_registry.dart';

WindowsApplicationRegistry createChromeRegistry({bool chromeExists = true}) {
  return WindowsApplicationRegistry(
    environment: const {'ProgramFiles': r'C:\Program Files'},
    fileExists: (_) => chromeExists,
  );
}

WindowsApplicationRegistry createApplicationRegistry({bool appsExist = true}) {
  return WindowsApplicationRegistry(
    environment: const {
      'ProgramFiles': r'C:\Program Files',
      'ProgramFiles(x86)': r'C:\Program Files (x86)',
      'LOCALAPPDATA': r'C:\Users\test\AppData\Local',
      'SystemRoot': r'C:\Windows',
    },
    fileExists: (_) => appsExist,
  );
}

final class MockApplicationLauncher implements ApplicationLauncher {
  MockApplicationLauncher({this.shouldSucceed = true});

  final bool shouldSucceed;
  int launchCount = 0;
  ResolvedApplication? launchedApplication;

  @override
  Future<Result<ApplicationLaunchReceipt>> launch(
    ResolvedApplication application,
  ) async {
    launchCount++;
    launchedApplication = application;
    if (!shouldSucceed) {
      return const Result.failure(
        Failure('Mock launch failed.', code: 'launch_failed'),
      );
    }
    return Result.success(
      ApplicationLaunchReceipt(
        applicationId: application.descriptor.id,
        processId: 1234,
      ),
    );
  }
}
