import 'package:ai_os/agents/agent.dart';
import 'package:ai_os/agents/browser_agent/browser_agent.dart';
import 'package:ai_os/ai/model_provider/model_provider.dart';
import 'package:ai_os/browser/browser_session.dart';
import 'package:ai_os/browser/chrome/chrome_profile_tools.dart';
import 'package:ai_os/core/events/app_event.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/browser/inspect_browser_context_tool.dart';
import 'package:ai_os/tools/tool.dart';
import 'package:ai_os/tools/windows/discovery/window_info.dart';
import 'package:ai_os/tools/windows/ui_automation/ui_element.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chrome_fakes.dart';
import 'support/ui_automation_fakes.dart';
import 'support/window_discovery_fakes.dart';

const _chromeWindow = WindowInfo(
  id: 'windows:window:abc',
  title: 'Example - Google Chrome',
  processId: 10,
  processName: 'chrome.exe',
  applicationId: 'chrome',
  isVisible: true,
  isMinimized: false,
  isMaximized: false,
  isActive: true,
);

const _edgeWindow = WindowInfo(
  id: 'windows:window:def',
  title: 'Example - Microsoft Edge',
  processId: 11,
  processName: 'msedge.exe',
  applicationId: 'edge',
  isVisible: true,
  isMinimized: false,
  isMaximized: true,
  isActive: false,
);

const _notepadWindow = WindowInfo(
  id: 'windows:window:123',
  title: 'Notes',
  processId: 12,
  processName: 'notepad.exe',
  applicationId: 'notepad',
  isVisible: true,
  isMinimized: false,
  isMaximized: false,
  isActive: true,
);

final class _UnusedProvider implements ModelProvider {
  int callCount = 0;

  @override
  String get id => 'unused-browser-context';

  @override
  Future<Result<ModelResponse>> generate(ModelRequest request) async {
    callCount++;
    return const Result.failure(Failure('Model must not be called.'));
  }
}

void main() {
  test(
    'identifies the active Chrome window and returns structured data',
    () async {
      final events = EventBus();
      final automation = MockUiAutomation();
      final tool = _tool(
        events,
        automation,
        MockWindowDiscovery(listResult: const Result.success([_chromeWindow])),
      );

      final result = await _execute(tool);

      expect(result.isSuccess, isTrue);
      final data = result.fold((output) => output.data, (_) => const {});
      expect(data['browser'], 'chrome');
      expect(data['window_id'], _chromeWindow.id);
      expect(data['title'], _chromeWindow.title);
      expect(data['element_count'], MockUiAutomation.tree.length);
      expect(data['elements'], isA<List<Object?>>());
      await events.close();
    },
  );

  test('identifies an explicitly selected Edge window', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final tool = _tool(
      events,
      automation,
      MockWindowDiscovery(
        listResult: const Result.success([_chromeWindow, _edgeWindow]),
      ),
    );

    final result = await _execute(tool, {'window_id': _edgeWindow.id});

    expect(
      result.fold((output) => output.data['browser'], (_) => null),
      'edge',
    );
    expect(automation.inspectCallCount, 1);
    await events.close();
  });

  test('rejects an explicitly selected non-browser window', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final tool = _tool(
      events,
      automation,
      MockWindowDiscovery(listResult: const Result.success([_notepadWindow])),
    );

    final result = await _execute(tool, {'window_id': _notepadWindow.id});

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'not_browser_window',
    );
    expect(automation.inspectCallCount, 0);
    await events.close();
  });

  test(
    'requires an active allow-listed browser when no ID is supplied',
    () async {
      final events = EventBus();
      final automation = MockUiAutomation();
      final inactiveChrome = WindowInfo(
        id: _chromeWindow.id,
        title: _chromeWindow.title,
        processId: _chromeWindow.processId,
        processName: _chromeWindow.processName,
        applicationId: _chromeWindow.applicationId,
        isVisible: true,
        isMinimized: false,
        isMaximized: false,
        isActive: false,
      );
      final tool = _tool(
        events,
        automation,
        MockWindowDiscovery(
          listResult: Result.success([_notepadWindow, inactiveChrome]),
        ),
      );

      final result = await _execute(tool);

      expect(
        result.fold((_) => null, (failure) => failure.code),
        'browser_window_not_found',
      );
      expect(automation.inspectCallCount, 0);
      await events.close();
    },
  );

  test('passes and defensively enforces traversal bounds', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final tool = _tool(
      events,
      automation,
      MockWindowDiscovery(listResult: const Result.success([_chromeWindow])),
    );

    final result = await _execute(tool, {'max_depth': 1, 'max_elements': 2});

    final data = result.fold((output) => output.data, (_) => const {});
    expect(automation.lastMaxDepth, 1);
    expect(automation.lastMaxElements, 2);
    expect(data['element_count'], 2);
    expect(data['was_truncated'], isTrue);
    await events.close();
  });

  test(
    'password elements expose metadata but no value-bearing fields',
    () async {
      final events = EventBus();
      final passwordElement = UiElement(
        id: 'uia:password:0',
        name: 'Password',
        automationId: 'must-not-be-returned',
        className: 'PasswordBox',
        controlType: UiControlType.edit,
        isEnabled: true,
        isVisible: true,
        isFocused: true,
        isPassword: true,
        isValueReadOnly: false,
        depth: 0,
        supportedPatterns: const {UiPattern.value},
      );
      final tool = _tool(
        events,
        MockUiAutomation(elements: [passwordElement]),
        MockWindowDiscovery(listResult: const Result.success([_chromeWindow])),
      );

      final result = await _execute(tool);
      final data = result.fold((output) => output.data, (_) => const {});
      final elements = data['elements']! as List<Object?>;
      final element = elements.single! as Map<String, Object?>;

      expect(element['role'], 'password');
      expect(element['name'], 'Password');
      expect(element['depth'], 0);
      expect(element, contains('parent_id'));
      expect(element['is_password'], isTrue);
      expect(element, isNot(contains('value')));
      expect(element, isNot(contains('automation_id')));
      expect(element, isNot(contains('class_name')));
      await events.close();
    },
  );

  test('read permission denial prevents discovery and inspection', () async {
    final events = EventBus();
    final discovery = MockWindowDiscovery(
      listResult: const Result.success([_chromeWindow]),
    );
    final automation = MockUiAutomation();
    final tool = _tool(events, automation, discovery);

    final result = await tool.execute(
      const {},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.execute}),
      ),
    );

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'permission_denied',
    );
    expect(discovery.listCallCount, 0);
    expect(automation.inspectCallCount, 0);
    await events.close();
  });

  test('forwards inspection failures and emits sanitized lifecycle', () async {
    final events = EventBus();
    final observed = <ApplicationEvent>[];
    final subscription = events.events.listen((event) {
      if (event is ApplicationEvent) observed.add(event);
    });
    final tool = _tool(
      events,
      MockUiAutomation(
        failure: const Failure('Inspection failed.', code: 'inspection_failed'),
      ),
      MockWindowDiscovery(listResult: const Result.success([_chromeWindow])),
    );

    final result = await _execute(tool);

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'inspection_failed',
    );
    expect(observed.map((event) => event.type), [
      'browser.context.inspection.started',
      'browser.context.inspection.failed',
    ]);
    expect(observed.last.data, isNot(contains('message')));
    await subscription.cancel();
    await events.close();
  });

  test(
    'Browser Agent and Orchestrator route inspection with event ordering',
    () async {
      final events = EventBus();
      final observed = <ApplicationEvent>[];
      final subscription = events.events.listen((event) {
        if (event is ApplicationEvent) observed.add(event);
      });
      final tool = _tool(
        events,
        MockUiAutomation(),
        MockWindowDiscovery(listResult: const Result.success([_chromeWindow])),
      );
      final agent = _agent(events, tool);
      final provider = _UnusedProvider();
      final orchestrator = Orchestrator(
        modelProvider: provider,
        events: events,
        agents: [agent],
        tools: agent.availableTools,
      );

      final agentResult = await agent.handle(
        const InspectBrowserContextAgentRequest(maxDepth: 1, maxElements: 2),
      );
      expect(agentResult.isSuccess, isTrue);
      observed.clear();

      final result = await orchestrator.executeCommand(
        const InspectBrowserContextCommand(maxDepth: 1, maxElements: 2),
      );

      expect(result.isSuccess, isTrue);
      expect(provider.callCount, 0);
      expect(observed.map((event) => event.type), [
        'browser.context.inspection.requested',
        'browser.context.inspection.started',
        'browser.context.inspection.succeeded',
      ]);
      expect(observed.last.data, isNot(contains('title')));
      expect(observed.last.data, isNot(contains('elements')));
      await subscription.cancel();
      await events.close();
    },
  );

  test(
    'interpreter recognizes only the approved browser inspection phrases',
    () {
      const interpreter = DeterministicCommandInterpreter();
      for (final request in const [
        'inspect browser',
        'Inspect my browser.',
        "What's open in my browser?",
      ]) {
        final result = interpreter.interpret(request);
        expect(result.isSuccess, isTrue, reason: request);
        expect(
          result.fold((command) => command, (_) => null),
          isA<InspectBrowserContextCommand>(),
        );
      }
      expect(
        interpreter.interpret('inspect Chrome passwords').isFailure,
        isTrue,
      );
      expect(interpreter.interpret('read every browser tab').isFailure, isTrue);
    },
  );
}

InspectBrowserContextTool _tool(
  EventBus events,
  MockUiAutomation automation,
  MockWindowDiscovery discovery,
) => InspectBrowserContextTool(
  windowDiscovery: discovery,
  uiAutomation: automation,
  events: events,
);

Future<Result<ToolOutput>> _execute(
  InspectBrowserContextTool tool, [
  Map<String, Object?> input = const {},
]) => tool.execute(
  input,
  ToolExecutionContext(
    authorizer: AllowListPermissionAuthorizer({Permission.read}),
  ),
);

BrowserAgent _agent(EventBus events, InspectBrowserContextTool tool) {
  final registry = MockChromeProfileRegistry();
  return BrowserAgent(
    authorizer: AllowListPermissionAuthorizer({Permission.read}),
    discoverChromeProfilesTool: DiscoverChromeProfilesTool(
      registry: registry,
      events: events,
    ),
    launchChromeProfileTool: LaunchChromeProfileTool(
      launcher: MockChromeLauncher(),
      session: BrowserSession(),
      events: events,
    ),
    inspectBrowserContextTool: tool,
  );
}

