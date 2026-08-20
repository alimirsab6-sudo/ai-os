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

  test('default descriptors expose stable allow-listed aliases', () {
    final descriptors = {
      for (final descriptor in WindowsApplicationRegistry.defaultApplications)
        descriptor.id: descriptor,
    };

    expect(
      descriptors['chrome']!.aliases,
      containsAll(['chrome', 'google chrome']),
    );
    expect(
      descriptors['edge']!.aliases,
      containsAll(['edge', 'microsoft edge']),
    );
    expect(descriptors['notepad']!.aliases, contains('notepad'));
    expect(
      descriptors['calculator']!.aliases,
      containsAll(['calculator', 'calc']),
    );
    expect(
      descriptors['file_explorer']!.aliases,
      containsAll(['file explorer', 'my pc']),
    );
    expect(descriptors['settings']!.aliases, contains('windows settings'));
    expect(descriptors['task_manager']!.aliases, contains('task manager'));
    for (final descriptor in descriptors.values) {
      expect(descriptor.locations, isNotEmpty, reason: descriptor.id);
      expect(descriptor.executableNames, isNotEmpty, reason: descriptor.id);
    }
    expect(
      descriptors['task_manager']!.launchStrategy,
      ApplicationLaunchStrategy.windowsRunAs,
    );
    for (final descriptor in descriptors.values.where(
      (descriptor) => descriptor.id != 'task_manager',
    )) {
      expect(
        descriptor.launchStrategy,
        ApplicationLaunchStrategy.directProcess,
        reason: descriptor.id,
      );
    }
  });

  test('resolves every default application only through known roots', () {
    final registry = WindowsApplicationRegistry(
      environment: const {
        'ProgramFiles': r'C:\Program Files',
        'ProgramFiles(x86)': r'C:\Program Files (x86)',
        'LOCALAPPDATA': r'C:\Users\test\AppData\Local',
        'SystemRoot': r'C:\Windows',
      },
      fileExists: (_) => true,
    );

    for (final descriptor in WindowsApplicationRegistry.defaultApplications) {
      final result = registry.resolve(descriptor.id);
      expect(result.isSuccess, isTrue, reason: descriptor.id);
      expect(
        result.fold((value) => value.descriptor.id, (_) => null),
        descriptor.id,
      );
    }
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

