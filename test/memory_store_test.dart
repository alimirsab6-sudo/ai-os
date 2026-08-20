import 'package:ai_os/memory/memory_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('in-memory store supports store, retrieve, and delete', () async {
    final store = InMemoryStore();

    expect((await store.store('key', 'value')).isSuccess, isTrue);
    expect(
      (await store.retrieve('key')).fold((value) => value, (_) => null),
      'value',
    );
    expect((await store.delete('key')).isSuccess, isTrue);
    expect(
      (await store.retrieve('key')).fold((value) => value, (_) => 'failed'),
      isNull,
    );
  });
}

