enum ExecutableResolutionStrategy { windowsKnownLocations }

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
    this.executableNames = const [],
  });

  final String id;
  final String displayName;
  final ExecutableResolutionStrategy resolutionStrategy;
  final List<ExecutableLocation> locations;
  final List<String> executableNames;
}

final class ResolvedApplication {
  const ResolvedApplication({
    required this.descriptor,
    required this.executablePath,
  });

  final ApplicationDescriptor descriptor;
  final String executablePath;
}
