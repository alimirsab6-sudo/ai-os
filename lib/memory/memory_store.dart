import '../core/result.dart';

abstract interface class MemoryStore {
  Future<Result<void>> store(String key, Object value);
  Future<Result<Object?>> retrieve(String key);
  Future<Result<void>> delete(String key);
}

final class InMemoryStore implements MemoryStore {
  final Map<String, Object> _values = {};

  @override
  Future<Result<void>> store(String key, Object value) async {
    if (key.trim().isEmpty) {
      return const Result.failure(
        Failure('Memory keys cannot be empty.', code: 'invalid_key'),
      );
    }
    _values[key] = value;
    return const Result.success(null);
  }

  @override
  Future<Result<Object?>> retrieve(String key) async =>
      Result.success(_values[key]);

  @override
  Future<Result<void>> delete(String key) async {
    _values.remove(key);
    return const Result.success(null);
  }
}

