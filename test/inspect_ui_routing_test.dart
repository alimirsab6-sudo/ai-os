import 'package:ai_os/agents/agent.dart';
import 'package:ai_os/agents/pc_agent/pc_agent.dart';
import 'package:ai_os/ai/model_provider/model_provider.dart';
import 'package:ai_os/core/events/app_event.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/windows/inspect_ui_tool.dart';
import 'package:ai_os/tools/windows/launch_application_tool.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pc_agent_fakes.dart';
import 'support/ui_automation_fakes.dart';
import 'support/window_discovery_fakes.dart';

const windowId = 'windows:window:123';

final class UnusedUiModelProvider implements ModelProvider {
  int callCount = 0;

  @override
  String get id => 'unused-ui';

  @override
  Future<Result<ModelResponse>> generate(ModelRequest request) async {
    callCount++;
    return const Result.failure(Failure('Model call was not expected.'));
  }
}

void main() {
  test('PC Agent routes InspectUiAgentRequest to InspectUiTool', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final agent = _createAgent(events, automation);

    final result = await agent.handle(
      const InspectUiAgentRequest(
        windowId: windowId,
        maxDepth: 2,
        maxElements: 3,
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(automation.inspectCallCount, 1);
    expect(automation.lastMaxDepth, 2);
    expect(automation.lastMaxElements, 3);
    expect(
      agent.availableTools.map((tool) => tool.id),
      contains('windows.inspect_ui'),
    );
    await events.close();
  });

  test(
    'Orchestrator routes inspection without using the model provider',
    () async {
      final events = EventBus();
      final automation = MockUiAutomation();
      final agent = _createAgent(events, automation);
      final provider = UnusedUiModelProvider();
      final orchestrator = Orchestrator(
        modelProvider: provider,
        events: events,
        agents: [agent],
        tools: agent.availableTools,
      );

      final result = await orchestrator.executeCommand(
        const InspectUiCommand(
          windowId: windowId,
          maxDepth: 2,
          maxElements: 20,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(provider.callCount, 0);
      expect(
        result.fold((value) => value.data['element_count'], (_) => null),
        5,
      );
      await events.close();
    },
  );

  test('Orchestrator and tool emit full successful lifecycle', () async {
    final events = EventBus();
    final observed = <ApplicationEvent>[];
    final subscription = events.events.listen((event) {
      if (event is ApplicationEvent) observed.add(event);
    });
    final agent = _createAgent(events, MockUiAutomation());
    final orchestrator = Orchestrator(
      modelProvider: UnusedUiModelProvider(),
      events: events,
      agents: [agent],
    );

    await orchestrator.executeCommand(
      const InspectUiCommand(windowId: windowId, maxDepth: 2, maxElements: 20),
    );

    expect(observed.map((event) => event.type), [
      'ui.inspection.requested',
      'ui.inspection.started',
      'ui.inspection.succeeded',
    ]);
    expect(observed.last.data['element_count'], 5);
    expect(observed.last.data['window_id'], windowId);
    await subscription.cancel();
    await events.close();
  });
}

PcAgent _createAgent(EventBus events, MockUiAutomation automation) {
  final launchTool = LaunchApplicationTool(
    registry: createChromeRegistry(),
    launcher: MockApplicationLauncher(),
    events: events,
  );
  return PcAgent(
    launchApplicationTool: launchTool,
    authorizer: AllowListPermissionAuthorizer({Permission.read}),
    inspectUiTool: InspectUiTool(
      uiAutomation: automation,
      windowDiscovery: MockWindowDiscovery(),
      events: events,
    ),
  );
}

