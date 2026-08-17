import 'dart:io';

import '../../../core/result.dart';
import 'application_descriptor.dart';
import 'application_registry.dart';

typedef FileExists = bool Function(String path);

bool _defaultFileExists(String path) => File(path).existsSync();

/// Resolves allow-listed applications from fixed paths under Windows roots.
final class WindowsApplicationRegistry implements ApplicationRegistry {
  WindowsApplicationRegistry({
    Map<String, String>? environment,
    FileExists? fileExists,
    bool registerDefaults = true,
  }) : _environment = environment ?? Platform.environment,
       _fileExists = fileExists ?? _defaultFileExists {
    if (registerDefaults) {
      for (final descriptor in defaultApplications) {
        register(descriptor);
      }
    }
  }

  static const List<ApplicationDescriptor> defaultApplications = [
    chromeDescriptor,
    edgeDescriptor,
    notepadDescriptor,
    calculatorDescriptor,
    fileExplorerDescriptor,
    settingsDescriptor,
    taskManagerDescriptor,
  ];

  static const ApplicationDescriptor chromeDescriptor = ApplicationDescriptor(
    id: 'chrome',
    displayName: 'Google Chrome',
    resolutionStrategy: ExecutableResolutionStrategy.windowsKnownLocations,
    locations: [
      ExecutableLocation(
        environmentVariable: 'ProgramFiles',
        relativePath: r'Google\Chrome\Application\chrome.exe',
      ),
      ExecutableLocation(
        environmentVariable: 'ProgramFiles(x86)',
        relativePath: r'Google\Chrome\Application\chrome.exe',
      ),
      ExecutableLocation(
        environmentVariable: 'LOCALAPPDATA',
        relativePath: r'Google\Chrome\Application\chrome.exe',
      ),
    ],
    aliases: ['chrome', 'google chrome', 'browser'],
    executableNames: ['chrome.exe'],
  );

  static const ApplicationDescriptor edgeDescriptor = ApplicationDescriptor(
    id: 'edge',
    displayName: 'Microsoft Edge',
    resolutionStrategy: ExecutableResolutionStrategy.windowsKnownLocations,
    locations: [
      ExecutableLocation(
        environmentVariable: 'ProgramFiles(x86)',
        relativePath: r'Microsoft\Edge\Application\msedge.exe',
      ),
      ExecutableLocation(
        environmentVariable: 'ProgramFiles',
        relativePath: r'Microsoft\Edge\Application\msedge.exe',
      ),
      ExecutableLocation(
        environmentVariable: 'LOCALAPPDATA',
        relativePath: r'Microsoft\Edge\Application\msedge.exe',
      ),
    ],
    aliases: ['edge', 'microsoft edge'],
    executableNames: ['msedge.exe'],
  );

  static const ApplicationDescriptor notepadDescriptor = ApplicationDescriptor(
    id: 'notepad',
    displayName: 'Notepad',
    resolutionStrategy: ExecutableResolutionStrategy.windowsKnownLocations,
    locations: [
      ExecutableLocation(
        environmentVariable: 'SystemRoot',
        relativePath: r'System32\notepad.exe',
      ),
    ],
    aliases: ['notepad'],
    executableNames: ['notepad.exe'],
  );

  static const ApplicationDescriptor calculatorDescriptor =
      ApplicationDescriptor(
        id: 'calculator',
        displayName: 'Calculator',
        resolutionStrategy: ExecutableResolutionStrategy.windowsKnownLocations,
        locations: [
          ExecutableLocation(
            environmentVariable: 'SystemRoot',
            relativePath: r'System32\calc.exe',
          ),
        ],
        aliases: ['calculator', 'calc'],
        executableNames: ['calc.exe', 'calculatorapp.exe'],
      );

  static const ApplicationDescriptor fileExplorerDescriptor =
      ApplicationDescriptor(
        id: 'file_explorer',
        displayName: 'File Explorer',
        resolutionStrategy: ExecutableResolutionStrategy.windowsKnownLocations,
        locations: [
          ExecutableLocation(
            environmentVariable: 'SystemRoot',
            relativePath: 'explorer.exe',
          ),
        ],
        aliases: ['file explorer', 'explorer', 'my pc'],
        executableNames: ['explorer.exe'],
      );

  static const ApplicationDescriptor settingsDescriptor = ApplicationDescriptor(
    id: 'settings',
    displayName: 'Windows Settings',
    resolutionStrategy: ExecutableResolutionStrategy.windowsKnownLocations,
    locations: [
      ExecutableLocation(
        environmentVariable: 'SystemRoot',
        relativePath: r'ImmersiveControlPanel\SystemSettings.exe',
      ),
    ],
    aliases: ['settings', 'windows settings'],
    executableNames: ['systemsettings.exe'],
  );

  static const ApplicationDescriptor taskManagerDescriptor =
      ApplicationDescriptor(
        id: 'task_manager',
        displayName: 'Task Manager',
        resolutionStrategy: ExecutableResolutionStrategy.windowsKnownLocations,
        locations: [
          ExecutableLocation(
            environmentVariable: 'SystemRoot',
            relativePath: r'System32\Taskmgr.exe',
          ),
        ],
        aliases: ['task manager', 'tasks'],
        executableNames: ['taskmgr.exe'],
        launchStrategy: ApplicationLaunchStrategy.windowsRunAs,
      );

  final Map<String, String> _environment;
  final FileExists _fileExists;
  final Map<String, ApplicationDescriptor> _applications = {};

  @override
  Result<void> register(ApplicationDescriptor application) {
    final id = application.id.trim().toLowerCase();
    if (id.isEmpty) {
      return const Result.failure(
        Failure(
          'Application IDs cannot be empty.',
          code: 'invalid_application',
        ),
      );
    }
    if (_applications.containsKey(id)) {
      return Result.failure(
        Failure(
          'Application "$id" is already registered.',
          code: 'application_already_registered',
        ),
      );
    }
    _applications[id] = application;
    return const Result.success(null);
  }

  @override
  Result<ApplicationDescriptor> findById(String applicationId) {
    final normalizedId = applicationId.trim().toLowerCase();
    final application = _applications[normalizedId];
    if (application == null) {
      return Result.failure(
        Failure(
          'Unknown application "$applicationId".',
          code: 'unknown_application',
        ),
      );
    }
    return Result.success(application);
  }

  @override
  List<ApplicationDescriptor> listKnownApplications() =>
      List.unmodifiable(_applications.values);

  @override
  Result<ResolvedApplication> resolve(String applicationId) {
    return findById(applicationId).fold(_resolveKnownLocations, Result.failure);
  }

  Result<ResolvedApplication> _resolveKnownLocations(
    ApplicationDescriptor application,
  ) {
    if (application.resolutionStrategy !=
        ExecutableResolutionStrategy.windowsKnownLocations) {
      return Result.failure(
        Failure(
          'Unsupported resolution strategy for ${application.displayName}.',
          code: 'unsupported_resolution_strategy',
        ),
      );
    }

    for (final location in application.locations) {
      final root = _environment[location.environmentVariable];
      if (root == null || root.trim().isEmpty) {
        continue;
      }
      final executablePath = '$root\\${location.relativePath}';
      if (_fileExists(executablePath)) {
        return Result.success(
          ResolvedApplication(
            descriptor: application,
            executablePath: executablePath,
          ),
        );
      }
    }

    return Result.failure(
      Failure(
        '${application.displayName} was not found in its known Windows '
        'installation locations.',
        code: 'application_not_found',
      ),
    );
  }
}
