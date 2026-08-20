import '../security/permission.dart';

final class LocalModelConfiguration {
  const LocalModelConfiguration({this.endpoint, this.modelName});

  final Uri? endpoint;
  final String? modelName;
}

final class StorageLocations {
  const StorageLocations({this.applicationData, this.cache});

  final String? applicationData;
  final String? cache;
}

/// Local settings consumed by the composition root and application services.
final class AppConfiguration {
  AppConfiguration({
    required this.selectedModelProvider,
    this.localModel = const LocalModelConfiguration(),
    Set<Permission> permissions = const {},
    Map<String, bool> featureFlags = const {},
    this.storageLocations = const StorageLocations(),
  }) : permissions = Set.unmodifiable(permissions),
       featureFlags = Map.unmodifiable(featureFlags);

  factory AppConfiguration.defaults() => AppConfiguration(
    selectedModelProvider: 'mock',
    permissions: {Permission.read, Permission.execute},
  );

  final String selectedModelProvider;
  final LocalModelConfiguration localModel;
  final Set<Permission> permissions;
  final Map<String, bool> featureFlags;
  final StorageLocations storageLocations;
}

