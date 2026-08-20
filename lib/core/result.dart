/// Details about an operation that could not be completed.
final class Failure {
  const Failure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => code == null ? message : '[$code] $message';
}

/// The outcome of an operation that can fail in an expected way.
sealed class Result<T> {
  const Result();

  const factory Result.success(T value) = Success<T>;
  const factory Result.failure(Failure failure) = Failed<T>;

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failed<T>;

  R fold<R>(
    R Function(T value) onSuccess,
    R Function(Failure failure) onFailure,
  ) => switch (this) {
    Success<T>(:final value) => onSuccess(value),
    Failed<T>(:final failure) => onFailure(failure),
  };
}

final class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;
}

final class Failed<T> extends Result<T> {
  const Failed(this.failure);

  final Failure failure;
}

