import 'package:ai_os/app/ai_os_app.dart';
import 'package:ai_os/ai/model_provider/mock_model_provider.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('temporary application shell starts', (tester) async {
    final events = EventBus();
    await tester.pumpWidget(
      AiOsApp(
        orchestrator: Orchestrator(
          modelProvider: const MockModelProvider(),
          events: events,
        ),
      ),
    );

    expect(find.text('Core architecture foundation'), findsOneWidget);
    await events.close();
  });
}
