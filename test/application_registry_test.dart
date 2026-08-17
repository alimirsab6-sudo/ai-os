import 'package:ai_os/tools/windows/applications/application_descriptor.dart';
import 'package:ai_os/tools/windows/applications/windows_application_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('looks up and lists registered applications by stable ID', () {
    final registry = WindowsApplicationRegistry(
      environment: const {},
      fileExists: (_) => false,
    );

    final lookup = registry.findById('CHROME');

    expect(lookup.isSuccess, isTrue);
    expect(
      lookup.fold((value) => value.displayName, (_) => null),
      'Google Chrome',
    );
    expect(
      registry.listKnownApplications().map((application) => application.id),
      containsAll(<String>{
        'chrome',
        'edge',
        'notepad',
        'calculator',
        'file_explorer',
        'settings',
        'task_manager',
      }),
    );
  });

  test('resolves Chrome only from a configured known Windows location', () {
    final registry = WindowsApplicationRegistry(
      environment: const {'LOCALAPPDATA': r'C:\Users\test\AppData\Local'},
      fileExists: (path) =>
          path ==
          r'C:\Users\test\AppData\Local\Google\Chrome\Application\chrome.exe',
    );

    final result = registry.resolve('chrome');

    expect(result.isSuccess, isTrue);
    expect(
      result.fold((value) => value.executablePath, (_) => null),
      endsWith(r'Google\Chrome\Application\chrome.exe'),
    );
  });

  test('unknown application returns a structured failure', () {
    final registry = WindowsApplicationRegistry(
      environment: const {},
      fileExists: (_) => false,
    );

    final result = registry.resolve('unknown');

    expect(result.isFailure, isTrue);
    expect(
      result.fold((_) => null, (failure) => failure.code),
      'unknown_application',
    );
  });

  test('supports registering an approved descriptor', () {
    final registry = WindowsApplicationRegistry(
      environment: const {},
      fileExists: (_) => false,
      registerDefaults: false,
    );
    const descriptor = ApplicationDescriptor(
      id: 'approved',
      displayName: 'Approved App',
      resolutionStrategy: ExecutableResolutionStrategy.windowsKnownLocations,
      locations: [],
    );

    expect(registry.register(descriptor).isSuccess, isTrue);
    expect(registry.findById('approved').isSuccess, isTrue);
  });
}
