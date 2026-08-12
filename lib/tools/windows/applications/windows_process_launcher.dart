import 'dart:io';

import '../../../core/result.dart';
import 'application_descriptor.dart';
import 'application_launcher.dart';

/// Starts a resolved executable directly; it never accepts shell commands.
final class WindowsProcessLauncher implements ApplicationLauncher {
  const WindowsProcessLauncher();

  @override
  Future<Result<ApplicationLaunchReceipt>> launch(
    ResolvedApplication application,
  ) async {
    if (!Platform.isWindows) {
      return const Result.failure(
        Failure(
          'Application launching is currently supported only on Windows.',
          code: 'unsupported_platform',
        ),
      );
    }

    try {
      final process = await Process.start(
        application.executablePath,
        const [],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return Result.success(
        ApplicationLaunchReceipt(
          applicationId: application.descriptor.id,
          processId: process.pid,
        ),
      );
    } on ProcessException catch (error) {
      return Result.failure(
        Failure(
          'Could not launch ${application.descriptor.displayName}: '
          '${error.message}',
          code: 'launch_failed',
        ),
      );
    } on FileSystemException catch (error) {
      return Result.failure(
        Failure(
          'Could not launch ${application.descriptor.displayName}: '
          '${error.message}',
          code: 'launch_failed',
        ),
      );
    }
  }
}
