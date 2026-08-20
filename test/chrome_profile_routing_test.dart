import 'package:ai_os/agents/browser_agent/browser_agent.dart';
import 'package:ai_os/agents/agent.dart';
import 'package:ai_os/ai/model_provider/model_provider.dart';
import 'package:ai_os/browser/browser_session.dart';
import 'package:ai_os/browser/chrome/chrome_profile_tools.dart';
import 'package:ai_os/core/events/app_event.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chrome_fakes.dart';

final class UnusedBrowserModelProvider implements ModelProvider {
  int callCount = 0;
  @override
  String get id => 'unused-browser';
  @override
  Future<Result<ModelResponse>> generate(ModelRequest request) async {
    callCount++;
    return const Result.failure(Failure('Model must not be called.'));
  }
}

void main() {
  test('Browser Agent routes discovery and profile launch', () async {
    final events = EventBus();
    final registry = MockChromeProfileRegistry();
    final launcher = MockChromeLauncher();
    final agent = _agent(events, registry, launcher);
    expect(
      (await agent.handle(
        const DiscoverChromeProfilesAgentRequest(),
      )).isSuccess,
      isTrue,
    );
    expect(
      (await agent.handle(
        const LaunchChromeProfileAgentRequest(
          profileId: 'chrome_profile_0123456789abcdef',
        ),
      )).isSuccess,
      isTrue,
    );
    expect(registry.discoveryCount, 1);
    expect(launcher.launchCount, 1);
    await events.close();
  });

  test(
    'Orchestrator routes commands without model and emits lifecycle',
    () async {
      final events = EventBus();
      final observed = <ApplicationEvent>[];
      final subscription = events.events.listen((event) {
        if (event is ApplicationEvent) observed.add(event);
      });
      final registry = MockChromeProfileRegistry();
      final launcher = MockChromeLauncher();
      final agent = _agent(events, registry, launcher);
      final provider = UnusedBrowserModelProvider();
      final orchestrator = Orchestrator(
        modelProvider: provider,
        events: events,
        agents: [agent],
        tools: agent.availableTools,
      );
      expect(
        (await orchestrator.executeCommand(
          const DiscoverChromeProfilesCommand(),
        )).isSuccess,
        isTrue,
      );
      expect(
        (await orchestrator.executeCommand(
          const LaunchChromeProfileCommand(
            profileId: 'chrome_profile_0123456789abcdef',
          ),
        )).isSuccess,
        isTrue,
      );
      expect(provider.callCount, 0);
      expect(observed.map((event) => event.type), [
        'chrome.profile.discovery.requested',
        'chrome.profile.discovery.started',
        'chrome.profile.discovery.succeeded',
        'chrome.profile.launch.requested',
        'chrome.profile.launch.started',
        'chrome.profile.launch.succeeded',
      ]);
      await subscription.cancel();
      await events.close();
    },
  );
}

BrowserAgent _agent(
  EventBus events,
  MockChromeProfileRegistry registry,
  MockChromeLauncher launcher,
) => BrowserAgent(
  authorizer: AllowListPermissionAuthorizer({
    Permission.read,
    Permission.execute,
  }),
  discoverChromeProfilesTool: DiscoverChromeProfilesTool(
    registry: registry,
    events: events,
  ),
  launchChromeProfileTool: LaunchChromeProfileTool(
    launcher: launcher,
    session: BrowserSession(),
    events: events,
  ),
);

