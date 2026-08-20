import 'package:ai_os/core/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('success carries a value', () {
    const result = Result<int>.success(42);

    expect(result.isSuccess, isTrue);
    expect(result.fold((value) => value, (_) => -1), 42);
  });

  test('failure carries a message and optional code', () {
    const result = Result<int>.failure(Failure('No value', code: 'missing'));

    expect(result.isFailure, isTrue);
    expect(result.fold((_) => '', (failure) => failure.code), 'missing');
  });
}

