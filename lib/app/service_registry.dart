/// Minimal type-based service registry for the application composition root.
final class ServiceRegistry {
  final Map<Type, Object> _services = {};

  void register<T extends Object>(T service) => _services[T] = service;

  T get<T extends Object>() {
    final service = _services[T];
    if (service == null) {
      throw StateError('No service registered for type $T.');
    }
    return service as T;
  }
}
