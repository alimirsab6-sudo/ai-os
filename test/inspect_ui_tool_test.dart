import 'package:ai_os/core/events/app_event.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/tool.dart';
import 'package:ai_os/tools/windows/inspect_ui_tool.dart';
import 'package:ai_os/tools/windows/ui_automation/ui_automation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ui_automation_fakes.dart';
import 'support/window_discovery_fakes.dart';

const windowId = 'windows:window:123';

void main() {
  test('mock UiAutomation supports root, children, lookup, and find', () async {
    final automation = MockUiAutomation();

    expect((await automation.getRootElement(windowId)).isSuccess, isTrue);
    expect(
      (await automation.getChildren(
        'uia:test:1',
      )).fold((elements) => elements.length, (_) => 0),
      2,
    );
    expect(
      (await automation.findElements(
        const UiElementQuery(automationId: 'saveButton'),
      )).fold((elements) => elements.single.name, (_) => null),
      'Save',
    );
    expect((await automation.getElement('uia:test:2')).isSuccess, isTrue);
  });

  test('InspectUiTool returns structured element data', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final tool = _tool(events, automation);

    final result = await tool.execute(const {
      'window_id': windowId,
      'max_depth': 2,
      'max_elements': 20,
    }, _readContext());

    expect(result.isSuccess, isTrue);
    expect(
      result.fold((output) => output.data['element_count'], (_) => null),
      4,
    );
    expect(automation.inspectCallCount, 1);
    await events.close();
  });

  test(
    'permission denial prevents discovery and UI Automation calls',
    () async {
      final events = EventBus();
      final discovery = MockWindowDiscovery();
      final automation = MockUiAutomation();
      final tool = InspectUiTool(
        uiAutomation: automation,
        windowDiscovery: discovery,
        events: events,
      );

      final result = await tool.execute(const {
        'window_id': windowId,
        'max_depth': 2,
        'max_elements': 20,
      }, ToolExecutionContext(authorizer: AllowListPermissionAuthorizer({})));

      expect(
        result.fold((_) => null, (failure) => failure.code),
        'permission_denied',
      );
      expect(discovery.listCallCount, 0);
      expect(automation.inspectCallCount, 0);
      await events.close();
    },
  );

  test('invalid runtime window ID is rejected', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final tool = _tool(events, automation);

    final result = await tool.execute(const {
      'window_id': '123',
      'max_depth': 2,
      'max_elements': 20,
    }, _readContext());

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'invalid_window_id',
    );
    expect(automation.inspectCallCount, 0);
    await events.close();
  });

  test('window discovery failure is returned before UI Automation', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final tool = InspectUiTool(
      uiAutomation: automation,
      windowDiscovery: MockWindowDiscovery(
        listResult: const Result.failure(
          Failure('Unavailable.', code: 'discovery_failed'),
        ),
      ),
      events: events,
    );

    final result = await tool.execute(const {
      'window_id': windowId,
      'max_depth': 2,
      'max_elements': 20,
    }, _readContext());

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'discovery_failed',
    );
    expect(automation.inspectCallCount, 0);
    await events.close();
  });

  test('depth limit constrains mock traversal', () async {
    final events = EventBus();
    final tool = _tool(events, MockUiAutomation());

    final result = await tool.execute(const {
      'window_id': windowId,
      'max_depth': 1,
      'max_elements': 20,
    }, _readContext());

    expect(
      result.fold((output) => output.data['element_count'], (_) => null),
      2,
    );
    expect(
      result.fold((output) => output.data['was_truncated'], (_) => null),
      isTrue,
    );
    await events.close();
  });

  test('element limit constrains mock traversal', () async {
    final events = EventBus();
    final tool = _tool(events, MockUiAutomation());

    final result = await tool.execute(const {
      'window_id': windowId,
      'max_depth': 5,
      'max_elements': 2,
    }, _readContext());

    expect(
      result.fold((output) => output.data['element_count'], (_) => null),
      2,
    );
    expect(
      result.fold((output) => output.data['was_truncated'], (_) => null),
      isTrue,
    );
    await events.close();
  });

  test('tool emits started and failed lifecycle events', () async {
    final events = EventBus();
    final observed = <ApplicationEvent>[];
    final subscription = events.events.listen((event) {
      if (event is ApplicationEvent) observed.add(event);
    });
    final tool = _tool(
      events,
      MockUiAutomation(
        failure: const Failure('Failed.', code: 'ui_inspection_failed'),
      ),
    );

    await tool.execute(const {
      'window_id': windowId,
      'max_depth': 2,
      'max_elements': 20,
    }, _readContext());

    expect(observed.map((event) => event.type), [
      'ui.inspection.started',
      'ui.inspection.failed',
    ]);
    expect(observed.last.data['window_id'], windowId);
    expect(observed.last.data['max_depth'], 2);
    expect(observed.last.data['max_elements'], 20);
    await subscription.cancel();
    await events.close();
  });

  test('traversal limits enforce global safety ceilings', () async {
    final events = EventBus();
    final tool = _tool(events, MockUiAutomation());

    final result = await tool.execute(const {
      'window_id': windowId,
      'max_depth': 11,
      'max_elements': 20,
    }, _readContext());

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'invalid_traversal_limit',
    );
    await events.close();
  });
}

InspectUiTool _tool(EventBus events, MockUiAutomation automation) =>
    InspectUiTool(
      uiAutomation: automation,
      windowDiscovery: MockWindowDiscovery(),
      events: events,
    );

ToolExecutionContext _readContext() => ToolExecutionContext(
  authorizer: AllowListPermissionAuthorizer({Permission.read}),
);
