import 'package:ai_os/core/events/app_event.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/tool.dart';
import 'package:ai_os/tools/windows/invoke_ui_element_tool.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ui_automation_fakes.dart';
import 'support/window_discovery_fakes.dart';

const windowId = 'windows:window:123';
const invokeElementId = 'uia:abc:2';

void main() {
  test('successfully invokes through mock UiAutomation', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final tool = _tool(events, automation);

    final result = await tool.execute(const {
      'window_id': windowId,
      'element_id': invokeElementId,
    }, _executeContext());

    expect(result.isSuccess, isTrue);
    expect(automation.invokeCallCount, 1);
    expect(automation.invokedWindowId, windowId);
    expect(automation.invokedElementId, invokeElementId);
    await events.close();
  });

  test('missing window ID fails validation', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final result = await _tool(
      events,
      automation,
    ).execute(const {'element_id': invokeElementId}, _executeContext());

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'missing_window_id',
    );
    expect(automation.invokeCallCount, 0);
    await events.close();
  });

  test('missing element ID fails validation', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final result = await _tool(
      events,
      automation,
    ).execute(const {'window_id': windowId}, _executeContext());

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'missing_element_id',
    );
    expect(automation.invokeCallCount, 0);
    await events.close();
  });

  test('invalid opaque element ID fails validation', () async {
    final events = EventBus();
    final result = await _tool(events, MockUiAutomation()).execute(const {
      'window_id': windowId,
      'element_id': 'raw-pointer',
    }, _executeContext());

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'invalid_element_id',
    );
    await events.close();
  });

  test('permission denial prevents discovery and invocation', () async {
    final events = EventBus();
    final discovery = MockWindowDiscovery();
    final automation = MockUiAutomation();
    final tool = InvokeUiElementTool(
      uiAutomation: automation,
      windowDiscovery: discovery,
      events: events,
    );

    final result = await tool.execute(const {
      'window_id': windowId,
      'element_id': invokeElementId,
    }, ToolExecutionContext(authorizer: AllowListPermissionAuthorizer({})));

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'permission_denied',
    );
    expect(discovery.listCallCount, 0);
    expect(automation.invokeCallCount, 0);
    await events.close();
  });

  test('stale element fails safely before invocation', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final result = await _tool(events, automation).execute(const {
      'window_id': windowId,
      'element_id': 'uia:abc:99',
    }, _executeContext());

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'stale_ui_element',
    );
    expect(automation.invokeCallCount, 0);
    await events.close();
  });

  test('element without Invoke pattern is rejected', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final result = await _tool(events, automation).execute(const {
      'window_id': windowId,
      'element_id': 'uia:abc:3',
    }, _executeContext());

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'invoke_not_supported',
    );
    expect(automation.invokeCallCount, 0);
    await events.close();
  });

  test('underlying Invoke failure is returned unchanged', () async {
    final events = EventBus();
    final automation = MockUiAutomation(
      invokeFailure: const Failure(
        'Provider failed.',
        code: 'ui_invoke_failed',
      ),
    );
    final result = await _tool(events, automation).execute(const {
      'window_id': windowId,
      'element_id': invokeElementId,
    }, _executeContext());

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'ui_invoke_failed',
    );
    expect(automation.invokeCallCount, 1);
    await events.close();
  });

  test('successful invoke emits structured lifecycle events', () async {
    final events = EventBus();
    final observed = <ApplicationEvent>[];
    final subscription = events.events.listen((event) {
      if (event is ApplicationEvent) observed.add(event);
    });

    await _tool(events, MockUiAutomation()).execute(const {
      'window_id': windowId,
      'element_id': invokeElementId,
    }, _executeContext());

    expect(observed.map((event) => event.type), [
      'ui.invoke.started',
      'ui.invoke.succeeded',
    ]);
    expect(observed.last.data['window_id'], windowId);
    expect(observed.last.data['element_id'], invokeElementId);
    expect(observed.last.data['success'], isTrue);
    await subscription.cancel();
    await events.close();
  });

  test(
    'failed invoke emits target and structured failure information',
    () async {
      final events = EventBus();
      final observed = <ApplicationEvent>[];
      final subscription = events.events.listen((event) {
        if (event is ApplicationEvent) observed.add(event);
      });

      await _tool(events, MockUiAutomation()).execute(const {
        'window_id': windowId,
        'element_id': 'uia:abc:99',
      }, _executeContext());

      expect(observed.map((event) => event.type), [
        'ui.invoke.started',
        'ui.invoke.failed',
      ]);
      expect(observed.last.data['window_id'], windowId);
      expect(observed.last.data['element_id'], 'uia:abc:99');
      expect(observed.last.data['success'], isFalse);
      expect(observed.last.data['failure_code'], 'stale_ui_element');
      await subscription.cancel();
      await events.close();
    },
  );
}

InvokeUiElementTool _tool(EventBus events, MockUiAutomation automation) =>
    InvokeUiElementTool(
      uiAutomation: automation,
      windowDiscovery: MockWindowDiscovery(),
      events: events,
    );

ToolExecutionContext _executeContext() => ToolExecutionContext(
  authorizer: AllowListPermissionAuthorizer({Permission.execute}),
);
