import 'package:ai_os/agents/agent.dart';
import 'package:ai_os/agents/pc_agent/pc_agent.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/windows/launch_application_tool.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pc_agent_fakes.dart';

void main() {
  test('routes a structured launch request to LaunchApplicationTool', () async {
    final events = EventBus();
    final launcher = MockApplicationLauncher();
    final agent = PcAgent(
      launchApplicationTool: LaunchApplicationTool(
        registry: createChromeRegistry(),
        launcher: launcher,
        events: events,
      ),
      authorizer: AllowListPermissionAuthorizer({Permission.execute}),
    );

    final result = await agent.handle(
      const LaunchApplicationAgentRequest(applicationId: 'chrome'),
    );

    expect(result.isSuccess, isTrue);
    expect(agent.availableTools.single.id, 'windows.launch_application');
    expect(launcher.launchCount, 1);
    await events.close();
  });
}

