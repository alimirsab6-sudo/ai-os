import 'package:ai_os/agents/agent.dart';
import 'package:ai_os/agents/pc_agent/pc_agent.dart';
import 'package:ai_os/ai/model_provider/model_provider.dart';
import 'package:ai_os/core/events/app_event.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/windows/invoke_ui_element_tool.dart';
import 'package:ai_os/tools/windows/launch_application_tool.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pc_agent_fakes.dart';
import 'support/ui_automation_fakes.dart';
import 'support/window_discovery_fakes.dart';

const windowId = 'windows:window:123';
const elementId = 'uia:abc:2';

final class UnusedInvokeModelProvider implements ModelProvider {
  int callCount = 0;
  @override
  String get id => 'unused-invoke';
  @override
  Future<Result<ModelResponse>> generate(ModelRequest request) async {
    callCount++;
    return const Result.failure(Failure('Model call was not expected.'));
  }
}

void main() {
  test('PC Agent routes InvokeUiElementAgentRequest', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final agent = _agent(events, automation);

    final result = await agent.handle(
      const InvokeUiElementAgentRequest(
        windowId: windowId,
        elementId: elementId,
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(automation.invokeCallCount, 1);
    expect(
      agent.availableTools.map((tool) => tool.id),
      contains('windows.invoke_ui_element'),
    );
    await events.close();
  });

  test(
    'Orchestrator routes invoke without a model call and emits lifecycle',
    () async {
      final events = EventBus();
      final observed = <ApplicationEvent>[];
      final subscription = events.events.listen((event) {
        if (event is ApplicationEvent) observed.add(event);
      });
      final automation = MockUiAutomation();
      final agent = _agent(events, automation);
      final provider = UnusedInvokeModelProvider();
      final orchestrator = Orchestrator(
        modelProvider: provider,
        events: events,
        agents: [agent],
        tools: agent.availableTools,
      );

      final result = await orchestrator.executeCommand(
        const InvokeUiElementCommand(windowId: windowId, elementId: elementId),
      );

      expect(result.isSuccess, isTrue);
      expect(provider.callCount, 0);
      expect(observed.map((event) => event.type), [
        'ui.invoke.requested',
        'ui.invoke.started',
        'ui.invoke.succeeded',
      ]);
      for (final event in observed) {
        expect(event.data['window_id'], windowId);
        expect(event.data['element_id'], elementId);
      }
      await subscription.cancel();
      await events.close();
    },
  );
}

PcAgent _agent(EventBus events, MockUiAutomation automation) {
  final launchTool = LaunchApplicationTool(
    registry: createChromeRegistry(),
    launcher: MockApplicationLauncher(),
    events: events,
  );
  return PcAgent(
    launchApplicationTool: launchTool,
    authorizer: AllowListPermissionAuthorizer({Permission.execute}),
    invokeUiElementTool: InvokeUiElementTool(
      uiAutomation: automation,
      windowDiscovery: MockWindowDiscovery(),
      events: events,
    ),
  );
}
