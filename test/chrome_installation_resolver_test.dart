import 'package:ai_os/browser/chrome/windows_chrome_installation_resolver.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/tools/windows/applications/application_descriptor.dart';
import 'package:ai_os/tools/windows/applications/application_registry.dart';
import 'package:ai_os/tools/windows/applications/windows_application_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves Chrome from a known Windows installation location', () {
    final resolver = WindowsChromeInstallationResolver(
      applications: WindowsApplicationRegistry(
        environment: const {'ProgramFiles': r'C:\Program Files'},
        fileExists: (_) => true,
      ),
    );
    expect(resolver.resolve().isSuccess, isTrue);
  });

  test('returns structured missing installation failure', () {
    final resolver = WindowsChromeInstallationResolver(
      applications: WindowsApplicationRegistry(
        environment: const {'ProgramFiles': r'C:\Program Files'},
        fileExists: (_) => false,
      ),
    );
    expect(
      resolver.resolve().fold((_) => null, (failure) => failure.code),
      'chrome_not_installed',
    );
  });

  test('rejects invalid resolved executable', () {
    final resolver = WindowsChromeInstallationResolver(
      applications: _InvalidChromeRegistry(),
    );
    expect(
      resolver.resolve().fold((_) => null, (failure) => failure.code),
      'invalid_chrome_installation',
    );
  });
}

final class _InvalidChromeRegistry implements ApplicationRegistry {
  static const descriptor = ApplicationDescriptor(
    id: 'chrome',
    displayName: 'Chrome',
    resolutionStrategy: ExecutableResolutionStrategy.windowsKnownLocations,
    locations: [],
    executableNames: ['chrome.exe'],
  );

  @override
  Result<ResolvedApplication> resolve(String applicationId) =>
      const Result.success(
        ResolvedApplication(
          descriptor: descriptor,
          executablePath: r'C:\Unsafe\other.exe',
        ),
      );
  @override
  Result<ApplicationDescriptor> findById(String applicationId) =>
      const Result.success(descriptor);
  @override
  List<ApplicationDescriptor> listKnownApplications() => const [descriptor];
  @override
  Result<void> register(ApplicationDescriptor application) =>
      const Result.success(null);
}
