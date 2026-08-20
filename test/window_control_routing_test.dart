import 'package:ai_os/agents/agent.dart';
import 'package:ai_os/agents/pc_agent/pc_agent.dart';
import 'package:ai_os/ai/model_provider/model_provider.dart';
import 'package:ai_os/core/events/app_event.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/windows/control/window_controller.dart';
import 'package:ai_os/tools/windows/launch_application_tool.dart';
import 'package:ai_os/tools/windows/window_control_tools.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pc_agent_fakes.dart';
import 'support/window_controller_fakes.dart';

const windowId = 'windows:window:abc';

final class UnusedControlModelProvider implements ModelProvider {
  int callCount = 0;

  @override
  String get id => 'unused-control';

  @override
  Future<Result<ModelResponse>> generate(ModelRequest request) async {
    callCount++;
    return const Result.failure(Failure('Model call was not expected.'));
  }
}

void main() {
  test('PC Agent routes all five structured window-control requests', () async {
    final events = EventBus();
    final controller = MockWindowController();
    final agent = _createAgent(events, controller);
    const requests = <AgentRequest>[
      ActivateWindowAgentRequest(windowId: windowId),
      MinimizeWindowAgentRequest(windowId: windowId),
      MaximizeWindowAgentRequest(windowId: windowId),
      RestoreWindowAgentRequest(windowId: windowId),
      CloseWindowAgentRequest(windowId: windowId),
    ];

    for (final request in requests) {
      expect((await agent.handle(request)).isSuccess, isTrue);
    }

    expect(
      controller.calls.map((call) => call.operation),
      WindowOperation.values,
    );
    expect(
      agent.availableTools.map((tool) => tool.id),
      containsAll([
        'windows.activate_window',
        'windows.minimize_window',
        'windows.maximize_window',
        'windows.restore_window',
        'windows.close_window',
      ]),
    );
    await events.close();
  });

  test(
    'Orchestrator routes all control commands without a model call',
    () async {
      final events = EventBus();
      final controller = MockWindowController();
      final agent = _createAgent(events, controller);
      final provider = UnusedControlModelProvider();
      final orchestrator = Orchestrator(
        modelProvider: provider,
        events: events,
        agents: [agent],
        tools: agent.availableTools,
      );
      const commands = <OrchestratorCommand>[
        ActivateWindowCommand(windowId: windowId),
        MinimizeWindowCommand(windowId: windowId),
        MaximizeWindowCommand(windowId: windowId),
        RestoreWindowCommand(windowId: windowId),
        CloseWindowCommand(windowId: windowId),
      ];

      for (final command in commands) {
        expect((await orchestrator.executeCommand(command)).isSuccess, isTrue);
      }

      expect(provider.callCount, 0);
      expect(controller.calls, hasLength(5));
      await events.close();
    },
  );

  test(
    'Orchestrator and tool emit complete structured lifecycle events',
    () async {
      final events = EventBus();
      final observed = <ApplicationEvent>[];
      final subscription = events.events.listen((event) {
        if (event is ApplicationEvent) {
          observed.add(event);
        }
      });
      final controller = MockWindowController();
      final agent = _createAgent(events, controller);
      final orchestrator = Orchestrator(
        modelProvider: UnusedControlModelProvider(),
        events: events,
        agents: [agent],
      );

      await orchestrator.executeCommand(
        const ActivateWindowCommand(windowId: windowId),
      );

      expect(observed.map((event) => event.type), [
        'window.control.requested',
        'window.control.started',
        'window.control.succeeded',
      ]);
      for (final event in observed) {
        expect(event.data['operation'], 'activate');
        expect(event.data['window_id'], windowId);
      }
      expect(observed.last.data['success'], isTrue);
      await subscription.cancel();
      await events.close();
    },
  );
}

PcAgent _createAgent(EventBus events, MockWindowController controller) {
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
      Permission.sensitive,
    }),
    activateWindowTool: ActivateWindowTool(
      controller: controller,
      events: events,
    ),
    minimizeWindowTool: MinimizeWindowTool(
      controller: controller,
      events: events,
    ),
    maximizeWindowTool: MaximizeWindowTool(
      controller: controller,
      events: events,
    ),
    restoreWindowTool: RestoreWindowTool(
      controller: controller,
      events: events,
    ),
    closeWindowTool: CloseWindowTool(controller: controller, events: events),
  );
}

