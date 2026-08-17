enum ExecutableResolutionStrategy { windowsKnownLocations }

enum ApplicationLaunchStrategy { directProcess, windowsRunAs }

final class ExecutableLocation {
  const ExecutableLocation({
    required this.environmentVariable,
    required this.relativePath,
  });

  final String environmentVariable;
  final String relativePath;
}

/// Allow-listed metadata used to identify and safely resolve an application.
final class ApplicationDescriptor {
  const ApplicationDescriptor({
    required this.id,
    required this.displayName,
    required this.resolutionStrategy,
    required this.locations,
    this.aliases = const [],
    this.executableNames = const [],
    this.launchStrategy = ApplicationLaunchStrategy.directProcess,
  });

  final String id;
  final String displayName;
  final ExecutableResolutionStrategy resolutionStrategy;
  final List<ExecutableLocation> locations;
  final List<String> aliases;
  final List<String> executableNames;
  final ApplicationLaunchStrategy launchStrategy;
}

final class ResolvedApplication {
  const ResolvedApplication({
    required this.descriptor,
    required this.executablePath,
  });

  final ApplicationDescriptor descriptor;
  final String executablePath;
}
