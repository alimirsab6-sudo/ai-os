import '../../core/result.dart';
import '../../tools/windows/applications/application_registry.dart';
import 'chrome_installation_resolver.dart';

final class WindowsChromeInstallationResolver
    implements ChromeInstallationResolver {
  const WindowsChromeInstallationResolver({required this.applications});

  final ApplicationRegistry applications;

  @override
  Result<ResolvedChromeInstallation> resolve() {
    final result = applications.resolve('chrome');
    return result.fold(
      (application) {
        final normalized = application.executablePath.replaceAll('/', '\\');
        if (application.descriptor.id != 'chrome' ||
            !normalized.toLowerCase().endsWith(r'\chrome.exe')) {
          return const Result.failure(
            Failure(
              'Chrome installation resolution returned an invalid executable.',
              code: 'invalid_chrome_installation',
            ),
          );
        }
        return Result.success(
          ResolvedChromeInstallation(executablePath: normalized),
        );
      },
      (failure) {
        return Result.failure(
          Failure(
            'Google Chrome is not installed in a known Windows location.',
            code: failure.code == 'application_not_found'
                ? 'chrome_not_installed'
                : 'chrome_resolution_failed',
          ),
        );
      },
    );
  }
}

