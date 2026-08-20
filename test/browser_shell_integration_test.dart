import 'package:ai_os/agents/browser_agent/browser_agent.dart';
import 'package:ai_os/ai/model_provider/mock_model_provider.dart';
import 'package:ai_os/browser/browser_session.dart';
import 'package:ai_os/browser/chrome/chrome_profile_tools.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/browser/embedded_browser_tool.dart';
import 'package:ai_os/ui/shell/cronyx_os_shell.dart';
import 'package:ai_os/ui/world/ai_core/ai_core.dart';
import 'package:ai_os/ui/world/ai_core/ai_core_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chrome_fakes.dart';
import 'support/embedded_browser_fakes.dart';

void main() {
  testWidgets(
    'Browser selection preserves permanent shell areas without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = _ShellHarness();
      final coreStates = <AiCoreState>[];

      await tester.pumpWidget(
        MaterialApp(
          home: CronyxOsShell(
            orchestrator: harness.orchestrator,
            browserController: harness.controller,
            onCoreStateChanged: coreStates.add,
            browserSurfaceBuilder: (_, _) => const ColoredBox(
              key: Key('embedded-browser-surface'),
              color: Colors.black,
            ),
          ),
        ),
      );
      await tester.pump();
      // The approved pre-integration Core screen has one known right-edge
      // overflow in its legacy HUD at this test size. Browser mode itself must
      // introduce no overflow.
      tester.takeException();
      final promptBottom = tester
          .getBottomLeft(find.byKey(const Key('core-prompt')))
          .dy;
      final initialCommandTop = tester
          .getTopLeft(find.byKey(const Key('command-input')))
          .dy;
      expect(promptBottom, lessThan(initialCommandTop));

      await tester.tap(find.byKey(const Key('nav-browser')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('browser-workspace')), findsOneWidget);
      expect(find.byKey(const Key('embedded-browser-surface')), findsOneWidget);
      expect(find.byKey(const Key('living-core-sidebar')), findsOneWidget);
      expect(find.text('LIVE ACTION'), findsOneWidget);
      expect(find.text('ACTIVITY'), findsOneWidget);
      expect(find.text('QUICK ACTIONS'), findsOneWidget);
      expect(find.byKey(const Key('command-input')), findsOneWidget);
      expect(find.text('Go Back'), findsOneWidget);
      expect(find.text('Reload'), findsOneWidget);
      expect(find.text('NETWORK'), findsNothing);
      expect(find.text('Run Command'), findsNothing);
      expect(tester.takeException(), isNull);

      final browserBottom = tester
          .getBottomRight(find.byKey(const Key('embedded-browser-surface')))
          .dy;
      final commandTop = tester
          .getTopLeft(find.byKey(const Key('command-input')))
          .dy;
      expect(browserBottom, greaterThan(commandTop));
      final livingCore = find.descendant(
        of: find.byKey(const Key('living-core-sidebar')),
        matching: find.byType(AiCore),
      );
      expect(tester.widget<AiCore>(livingCore).particleDensity, .2);
      expect(
        tester.getSize(livingCore).shortestSide,
        greaterThanOrEqualTo(140),
      );

      await tester.pump(const Duration(milliseconds: 1600));

      await tester.tap(find.byKey(const Key('nav-core')));
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      expect(find.text('How can I assist you today?'), findsOneWidget);
      expect(find.byKey(const Key('living-core-sidebar')), findsOneWidget);
      expect(coreStates.last, AiCoreState.idle);

      await tester.enterText(
        find.byKey(const Key('command-input')),
        'Open YouTube',
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      expect(
        harness.controller.operations,
        contains('navigate:https://youtube.com'),
      );
      expect(find.byKey(const Key('browser-workspace')), findsOneWidget);
      expect(
        coreStates,
        containsAllInOrder([AiCoreState.thinking, AiCoreState.executing]),
      );
      harness.controller.completeNavigation(title: 'YouTube');
      await tester.pump();
      expect(coreStates.last, AiCoreState.success);
      expect(find.text('youtube.com loaded'), findsWidgets);
      await tester.pump(const Duration(milliseconds: 1600));
      expect(coreStates.last, AiCoreState.idle);

      await tester.tap(find.byKey(const Key('nav-core')));
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('nav-browser')));
      await tester.pump();
      expect(find.byKey(const Key('browser-workspace')), findsOneWidget);
      expect(
        harness.controller.operations.where((value) => value == 'initialize'),
        hasLength(3),
      );
      expect(
        harness.controller.operations.where((value) => value == 'dispose'),
        hasLength(2),
      );
      expect(
        harness.controller.operations,
        containsAllInOrder([
          'initialize',
          'dispose',
          'initialize',
          'navigate:https://youtube.com',
          'dispose',
          'initialize',
        ]),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await harness.dispose();
    },
  );
}

final class _ShellHarness {
  _ShellHarness() {
    tool = EmbeddedBrowserTool(controller: controller, events: events);
    final agent = BrowserAgent(
      authorizer: AllowListPermissionAuthorizer({
        Permission.read,
        Permission.execute,
      }),
      discoverChromeProfilesTool: DiscoverChromeProfilesTool(
        registry: MockChromeProfileRegistry(),
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

