import 'package:ai_os/agents/agent.dart';
import 'package:ai_os/agents/pc_agent/pc_agent.dart';
import 'package:ai_os/ai/model_provider/model_provider.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/windows/launch_application_tool.dart';
import 'package:ai_os/tools/windows/window_discovery_tools.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pc_agent_fakes.dart';
import 'support/window_discovery_fakes.dart';

final class UnusedModelProvider implements ModelProvider {
  int callCount = 0;

  @override
  String get id => 'unused';

  @override
  Future<Result<ModelResponse>> generate(ModelRequest request) async {
    callCount++;
    return const Result.failure(Failure('Not expected.'));
  }
}

void main() {
  test('PC Agent routes list and active-window requests', () async {
    final events = EventBus();
    final discovery = MockWindowDiscovery();
    final agent = _createAgent(events, discovery);

    final listResult = await agent.handle(const ListWindowsAgentRequest());
    final activeResult = await agent.handle(
      const GetActiveWindowAgentRequest(),
    );

    expect(listResult.isSuccess, isTrue);
    expect(activeResult.isSuccess, isTrue);
    expect(discovery.listCallCount, 1);
    expect(discovery.activeCallCount, 1);
    expect(
      agent.availableTools.map((tool) => tool.id),
      containsAll(['windows.list_windows', 'windows.get_active_window']),
    );
    await events.close();
  });

  test(
    'Orchestrator routes ListWindowsCommand and emits lifecycle events',
    () async {
      final events = EventBus();
      final eventTypes = <String>[];
      final subscription = events.events.listen(
        (event) => eventTypes.add(event.type),
      );
      final discovery = MockWindowDiscovery();
      final provider = UnusedModelProvider();
      final agent = _createAgent(events, discovery);
      final orchestrator = Orchestrator(
        modelProvider: provider,
        events: events,
        agents: [agent],
        tools: agent.availableTools,
      );

      final result = await orchestrator.executeCommand(
        const ListWindowsCommand(),
      );

      expect(result.isSuccess, isTrue);
      expect(provider.callCount, 0);
      expect(
        result.fold((value) => value.data['window_count'], (_) => null),
        1,
      );
      expect(eventTypes, [
        'window.discovery.requested',
        'window.discovery.started',
        'window.discovery.succeeded',
      ]);
      await subscription.cancel();
      await events.close();
    },
  );

  test(
    'Orchestrator routes GetActiveWindowCommand without a model call',
    () async {
      final events = EventBus();
      final discovery = MockWindowDiscovery();
      final provider = UnusedModelProvider();
      final agent = _createAgent(events, discovery);
      final orchestrator = Orchestrator(
        modelProvider: provider,
        events: events,
        agents: [agent],
      );

      final result = await orchestrator.executeCommand(
        const GetActiveWindowCommand(),
      );

      expect(result.isSuccess, isTrue);
      expect(provider.callCount, 0);
      expect(
        result.fold(
          (value) =>
              (value.data['window'] as Map<String, Object?>)['is_active'],
          (_) => null,
        ),
        isTrue,
      );
      await events.close();
    },
  );

  test('failed discovery emits failure lifecycle event', () async {
    final events = EventBus();
    final eventTypes = <String>[];
    final subscription = events.events.listen(
      (event) => eventTypes.add(event.type),
    );
    final discovery = MockWindowDiscovery(
      listResult: const Result.failure(
        Failure('Unavailable.', code: 'discovery_failed'),
      ),
    );
    final agent = _createAgent(events, discovery);
    final orchestrator = Orchestrator(
      modelProvider: UnusedModelProvider(),
      events: events,
      agents: [agent],
    );

    final result = await orchestrator.executeCommand(
      const ListWindowsCommand(),
    );

    expect(result.isFailure, isTrue);
    expect(eventTypes, [
      'window.discovery.requested',
      'window.discovery.started',
      'window.discovery.failed',
    ]);
    await subscription.cancel();
    await events.close();
  });
}

PcAgent _createAgent(EventBus events, MockWindowDiscovery discovery) {
  final launchTool = LaunchApplicationTool(
    registry: createChromeRegistry(),
    launcher: MockApplicationLauncher(),
    events: events,
  );
  return PcAgent(
    launchApplicationTool: launchTool,
    authorizer: AllowListPermissionAuthorizer({
      Permission.read,
      Permission.execute,
    }),
    listWindowsTool: ListWindowsTool(discovery: discovery, events: events),
    getActiveWindowTool: GetActiveWindowTool(
      discovery: discovery,
      events: events,
    ),
  );
}

