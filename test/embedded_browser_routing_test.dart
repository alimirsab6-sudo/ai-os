import 'package:ai_os/agents/browser_agent/browser_agent.dart';
import 'package:ai_os/ai/model_provider/mock_model_provider.dart';
import 'package:ai_os/browser/browser_session.dart';
import 'package:ai_os/browser/chrome/chrome_profile_tools.dart';
import 'package:ai_os/browser/embedded/browser_controller.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/browser/embedded_browser_tool.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chrome_fakes.dart';
import 'support/embedded_browser_fakes.dart';

void main() {
  test('Browser Agent routes an embedded URL operation', () async {
    final harness = _BrowserHarness();

    final result = await harness.orchestrator.executeCommand(
      OpenUrlCommand(url: Uri.parse('https://example.com')),
    );

    expect(result.isSuccess, isTrue);
    expect(harness.controller.operations, [
      'initialize',
      'navigate:https://example.com',
    ]);
    await harness.dispose();
  });

  test(
    'Orchestrator maps known sites to the embedded browser without model',
    () async {
      final harness = _BrowserHarness();

      final result = await harness.orchestrator.handle('Open YouTube');

      expect(result.isSuccess, isTrue);
      expect(
        harness.controller.operations,
        contains('navigate:https://youtube.com'),
      );
      await harness.dispose();
    },
  );

  test('Orchestrator maps Google to the embedded browser', () async {
    final harness = _BrowserHarness();

    final result = await harness.orchestrator.handle('Open Google');

    expect(result.isSuccess, isTrue);
    expect(
      harness.controller.operations,
      contains('navigate:https://google.com'),
    );
    await harness.dispose();
  });

  test(
    'Orchestrator routes back forward and reload through Browser Agent',
    () async {
      final harness = _BrowserHarness();
      await harness.orchestrator.executeCommand(
        const InitializeBrowserCommand(),
      );
      harness.controller.emit(
        BrowserControllerState(
          isInitialized: true,
          loadingState: BrowserLoadingState.completed,
          currentUrl: Uri.parse('https://example.com'),
          canGoBack: true,
          canGoForward: true,
        ),
      );

      await harness.orchestrator.executeCommand(const BrowserBackCommand());
      harness.controller.completeNavigation();
      await harness.orchestrator.executeCommand(const BrowserForwardCommand());
      harness.controller.completeNavigation();
      await harness.orchestrator.executeCommand(const BrowserReloadCommand());
      harness.controller.completeNavigation();

      expect(harness.controller.operations, [
        'initialize',
        'back',
        'forward',
        'reload',
      ]);
      await harness.dispose();
    },
  );
}

final class _BrowserHarness {
  _BrowserHarness() {
    tool = EmbeddedBrowserTool(controller: controller, events: events);
    final registry = MockChromeProfileRegistry();
    final agent = BrowserAgent(
      authorizer: AllowListPermissionAuthorizer({
        Permission.read,
        Permission.execute,
      }),
      discoverChromeProfilesTool: DiscoverChromeProfilesTool(
        registry: registry,
        events: events,
      ),
      launchChromeProfileTool: LaunchChromeProfileTool(
        launcher: MockChromeLauncher(),
        session: BrowserSession(),
        events: events,
      ),
      embeddedBrowserTool: tool,
    );
    orchestrator = Orchestrator(
      modelProvider: const MockModelProvider(),
      events: events,
      agents: [agent],
      tools: agent.availableTools,
      commandInterpreter: const DeterministicCommandInterpreter(
        embeddedBrowserEnabled: true,
      ),
    );
  }

  final EventBus events = EventBus();
  final FakeBrowserController controller = FakeBrowserController();
  late final EmbeddedBrowserTool tool;
  late final Orchestrator orchestrator;

  Future<void> dispose() async {
    await controller.dispose();
    await controller.close();
    await events.close();
  }
}
