import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../../core/result.dart';
import 'application_descriptor.dart';
import 'application_launcher.dart';

typedef DirectProcessStarter = Future<int> Function(String executablePath);
typedef WindowsShellStarter = void Function(String executablePath);

Future<int> _startDirectProcess(String executablePath) async {
  final process = await Process.start(
    executablePath,
    const [],
    mode: ProcessStartMode.detached,
    runInShell: false,
  );
  return process.pid;
}

typedef _ShellExecuteWNative =
    IntPtr Function(
      IntPtr window,
      Pointer<Utf16> operation,
      Pointer<Utf16> file,
      Pointer<Utf16> parameters,
      Pointer<Utf16> directory,
      Int32 showCommand,
    );
typedef _ShellExecuteWDart =
    int Function(
      int window,
      Pointer<Utf16> operation,
      Pointer<Utf16> file,
      Pointer<Utf16> parameters,
      Pointer<Utf16> directory,
      int showCommand,
    );

void _startWithWindowsRunAs(String executablePath) {
  final shellExecute = DynamicLibrary.open(
    'shell32.dll',
  ).lookupFunction<_ShellExecuteWNative, _ShellExecuteWDart>('ShellExecuteW');
  final operation = 'runas'.toNativeUtf16();
  final file = executablePath.toNativeUtf16();
  try {
    final result = shellExecute(
      0,
      operation,
      file,
      nullptr.cast<Utf16>(),
      nullptr.cast<Utf16>(),
      1,
    );
    if (result <= 32) {
      throw ProcessException(
        executablePath,
        const [],
        'Windows rejected the approved application launch.',
        result,
      );
    }
  } finally {
    calloc.free(operation);
    calloc.free(file);
  }
}

/// Starts only resolved allow-listed executables using their declared strategy.
/// Neither strategy accepts a command line or raw user input.
final class WindowsProcessLauncher implements ApplicationLauncher {
  const WindowsProcessLauncher({
    this.directProcessStarter = _startDirectProcess,
    this.windowsShellStarter = _startWithWindowsRunAs,
  });

  final DirectProcessStarter directProcessStarter;
  final WindowsShellStarter windowsShellStarter;

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
      final int? processId;
      switch (application.descriptor.launchStrategy) {
        case ApplicationLaunchStrategy.directProcess:
          processId = await directProcessStarter(application.executablePath);
        case ApplicationLaunchStrategy.windowsRunAs:
          windowsShellStarter(application.executablePath);
          processId = null;
      }
      return Result.success(
        ApplicationLaunchReceipt(
          applicationId: application.descriptor.id,
          processId: processId,
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
