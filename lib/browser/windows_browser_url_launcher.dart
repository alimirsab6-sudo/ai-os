import 'dart:io';

import '../core/result.dart';
import '../tools/windows/applications/application_descriptor.dart';
import '../tools/windows/applications/application_registry.dart';
import 'browser_url_launcher.dart';

/// Opens a validated HTTP(S) URL through an allow-listed installed browser.
/// It starts the resolved executable directly and never invokes a shell.
final class WindowsBrowserUrlLauncher implements BrowserUrlLauncher {
  const WindowsBrowserUrlLauncher({required this.applications});

  final ApplicationRegistry applications;

  @override
  Future<Result<BrowserUrlLaunchReceipt>> launch(Uri url) async {
    if (!Platform.isWindows) {
      return const Result.failure(
        Failure(
          'Opening web addresses is currently supported only on Windows.',
          code: 'unsupported_platform',
        ),
      );
    }

    final browser = _resolveBrowser();
    if (browser case Failed(:final failure)) return Result.failure(failure);
    final application = (browser as Success<ResolvedApplication>).value;
    try {
      final process = await Process.start(
        application.executablePath,
        [url.toString()],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return Result.success(
        BrowserUrlLaunchReceipt(host: url.host, processId: process.pid),
      );
    } on ProcessException {
      return const Result.failure(
        Failure('The web address could not be opened.', code: 'launch_failed'),
      );
    } on FileSystemException {
      return const Result.failure(
        Failure('The web address could not be opened.', code: 'launch_failed'),
      );
    }
  }

  Result<ResolvedApplication> _resolveBrowser() {
    final edge = applications.resolve('edge');
    if (edge.isSuccess) return edge;
    return applications.resolve('chrome');
  }
}
