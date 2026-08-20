import 'package:ai_os/agents/pc_agent/pc_agent.dart';
import 'package:ai_os/ai/model_provider/model_provider.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/windows/launch_application_tool.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pc_agent_fakes.dart';

final class RecordingModelProvider implements ModelProvider {
  int callCount = 0;

  @override
  String get id => 'recording';

  @override
  Future<Result<ModelResponse>> generate(ModelRequest request) async {
    callCount++;
    return const Result.failure(Failure('Should not be called.'));
  }
}

void main() {
  test(
    'orchestrator routes command without an LLM and emits all events',
    () async {
      final events = EventBus();
      final eventTypes = <String>[];
      final subscription = events.events.listen(
        (event) => eventTypes.add(event.type),
      );
      final launcher = MockApplicationLauncher();
      final authorizer = AllowListPermissionAuthorizer({Permission.execute});
      final tool = LaunchApplicationTool(
        registry: createChromeRegistry(),
        launcher: launcher,
        events: events,
      );
      final provider = RecordingModelProvider();
      final orchestrator = Orchestrator(
        modelProvider: provider,
        events: events,
        agents: [PcAgent(launchApplicationTool: tool, authorizer: authorizer)],
        tools: [tool],
      );

      final result = await orchestrator.executeCommand(
        const LaunchApplicationCommand(applicationId: 'chrome'),
      );

      expect(result.isSuccess, isTrue);
      expect(provider.callCount, 0);
      expect(launcher.launchCount, 1);
      expect(eventTypes, [
        'pc.command.requested',
        'tool.started',
        'tool.succeeded',
        'application.launched',
      ]);
      await subscription.cancel();
      await events.close();
    },
  );

  test(
    'failed launch emits tool failed without application launched',
    () async {
      final events = EventBus();
      final eventTypes = <String>[];
      final subscription = events.events.listen(
        (event) => eventTypes.add(event.type),
      );
      final tool = LaunchApplicationTool(
        registry: createChromeRegistry(),
        launcher: MockApplicationLauncher(shouldSucceed: false),
        events: events,
      );
      final orchestrator = Orchestrator(
        modelProvider: RecordingModelProvider(),
        events: events,
        agents: [
          PcAgent(
            launchApplicationTool: tool,
            authorizer: AllowListPermissionAuthorizer({Permission.execute}),
          ),
        ],
      );

      final result = await orchestrator.executeCommand(
        const LaunchApplicationCommand(applicationId: 'chrome'),
      );

      expect(result.isFailure, isTrue);
      expect(eventTypes, [
        'pc.command.requested',
        'tool.started',
        'tool.failed',
      ]);
      await subscription.cancel();
      await events.close();
    },
  );

  test(
    'text command is interpreted then routed through the PC Agent',
    () async {
      final events = EventBus();
      final eventTypes = <String>[];
      final subscription = events.events.listen(
        (event) => eventTypes.add(event.type),
      );
      final launcher = MockApplicationLauncher();
      final tool = LaunchApplicationTool(
        registry: createChromeRegistry(),
        launcher: launcher,
        events: events,
      );
      final provider = RecordingModelProvider();
      final orchestrator = Orchestrator(
        modelProvider: provider,
        events: events,
        agents: [
          PcAgent(
            launchApplicationTool: tool,
            authorizer: AllowListPermissionAuthorizer({Permission.execute}),
          ),
        ],
        tools: [tool],
        commandInterpreter: const DeterministicCommandInterpreter(),
      );

      final result = await orchestrator.handle('Open Chrome');

      expect(result.isSuccess, isTrue);
      expect(provider.callCount, 0);
      expect(launcher.launchCount, 1);
      expect(eventTypes, [
        'orchestrator.request.received',
        'orchestrator.command.selected',
        'pc.command.requested',
        'tool.started',
        'tool.succeeded',
        'application.launched',
      ]);
      await subscription.cancel();
      await events.close();
    },
  );
}

