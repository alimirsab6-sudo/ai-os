import 'package:ai_os/ai/model_provider/mock_model_provider.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orchestrator coordinates a request through the provider', () async {
    final events = EventBus();
    final observedTypes = <String>[];
    final subscription = events.events.listen(
      (event) => observedTypes.add(event.type),
    );
    final orchestrator = Orchestrator(
      modelProvider: const MockModelProvider(responseText: 'ready'),
      events: events,
    );

    final result = await orchestrator.handle('status');

    expect(result.fold((value) => value.message, (_) => null), 'ready');
    expect(observedTypes, [
      'orchestrator.request.received',
      'orchestrator.response.completed',
    ]);
    await subscription.cancel();
    await events.close();
  });

  test(
    'orchestrator rejects an empty request without calling a service',
    () async {
      final events = EventBus();
      final orchestrator = Orchestrator(
        modelProvider: const MockModelProvider(),
        events: events,
      );

      final result = await orchestrator.handle('  ');

      expect(result.isFailure, isTrue);
      await events.close();
    },
  );
}

