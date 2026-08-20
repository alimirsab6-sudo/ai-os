import 'dart:convert';

import 'package:ai_os/core/events/app_event.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/tool.dart';
import 'package:ai_os/tools/windows/set_ui_element_value_tool.dart';
import 'package:ai_os/tools/windows/ui_automation/ui_automation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ui_automation_fakes.dart';
import 'support/window_discovery_fakes.dart';

const windowId = 'windows:window:123';
const valueElementId = 'uia:abc:3';
const secretValue = 'private-token-937';

void main() {
  test('successfully sets a value through mock UI Automation', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final result = await _tool(events, automation).execute(const {
      'window_id': windowId,
      'element_id': valueElementId,
      'value': 'AI OS test',
    }, _writeContext());

    expect(result.isSuccess, isTrue);
    expect(automation.setValueCallCount, 1);
    expect(automation.valueWindowId, windowId);
    expect(automation.valueElementId, valueElementId);
    expect(automation.setValueText, 'AI OS test');
    await events.close();
  });

  test('permission denial prevents discovery and SetValue', () async {
    final events = EventBus();
    final discovery = MockWindowDiscovery();
    final automation = MockUiAutomation();
    final tool = SetUiElementValueTool(
      uiAutomation: automation,
      windowDiscovery: discovery,
      events: events,
    );
    final result = await tool.execute(const {
      'window_id': windowId,
      'element_id': valueElementId,
      'value': secretValue,
    }, ToolExecutionContext(authorizer: AllowListPermissionAuthorizer({})));

    expect(_failureCode(result), 'permission_denied');
    expect(discovery.listCallCount, 0);
    expect(automation.setValueCallCount, 0);
    await events.close();
  });

  test('invalid window ID fails validation', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final result = await _tool(events, automation).execute(const {
      'window_id': '123',
      'element_id': valueElementId,
      'value': secretValue,
    }, _writeContext());
    expect(_failureCode(result), 'invalid_window_id');
    expect(automation.setValueCallCount, 0);
    await events.close();
  });

  test('invalid element ID fails validation', () async {
    final events = EventBus();
    final result = await _tool(events, MockUiAutomation()).execute(const {
      'window_id': windowId,
      'element_id': 'native-pointer',
      'value': secretValue,
    }, _writeContext());
    expect(_failureCode(result), 'invalid_element_id');
    await events.close();
  });

  test('missing and empty values fail validation', () async {
    final events = EventBus();
    final tool = _tool(events, MockUiAutomation());
    final missing = await tool.execute(const {
      'window_id': windowId,
      'element_id': valueElementId,
    }, _writeContext());
    final empty = await tool.execute(const {
      'window_id': windowId,
      'element_id': valueElementId,
      'value': '',
    }, _writeContext());
    expect(_failureCode(missing), 'missing_value');
    expect(_failureCode(empty), 'missing_value');
    await events.close();
  });

  test('very large values fail safely before execution', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final result = await _tool(events, automation).execute({
      'window_id': windowId,
      'element_id': valueElementId,
      'value': 'x' * (UiValueLimits.maximumCodeUnits + 1),
    }, _writeContext());
    expect(_failureCode(result), 'value_too_large');
    expect(automation.setValueCallCount, 0);
    await events.close();
  });

  test('stale element fails safely before SetValue', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final result = await _tool(events, automation).execute(const {
      'window_id': windowId,
      'element_id': 'uia:abc:99',
      'value': secretValue,
    }, _writeContext());
    expect(_failureCode(result), 'stale_ui_element');
    expect(automation.setValueCallCount, 0);
    await events.close();
  });

  test('element without Value pattern is rejected', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final result = await _tool(events, automation).execute(const {
      'window_id': windowId,
      'element_id': 'uia:abc:2',
      'value': secretValue,
    }, _writeContext());
    expect(_failureCode(result), 'value_not_supported');
    expect(automation.setValueCallCount, 0);
    await events.close();
  });

  test('read-only element is rejected before SetValue', () async {
    final events = EventBus();
    final automation = MockUiAutomation();
    final result = await _tool(events, automation).execute(const {
      'window_id': windowId,
      'element_id': 'uia:abc:4',
      'value': secretValue,
    }, _writeContext());
    expect(_failureCode(result), 'value_read_only');
    expect(automation.setValueCallCount, 0);
    await events.close();
  });

  test('underlying SetValue failure code is preserved without text', () async {
    final events = EventBus();
    final automation = MockUiAutomation(
      setValueFailure: const Failure(
        'Provider failed without echoing input.',
        code: 'ui_set_value_failed',
      ),
    );
    final result = await _tool(events, automation).execute(const {
      'window_id': windowId,
      'element_id': valueElementId,
      'value': secretValue,
    }, _writeContext());
    expect(_failureCode(result), 'ui_set_value_failed');
    expect(
      result.fold((_) => '', (failure) => failure.message),
      isNot(contains(secretValue)),
    );
    expect(automation.setValueCallCount, 1);
    await events.close();
  });

  test('lifecycle event payloads never contain submitted value', () async {
    final events = EventBus();
    final observed = <ApplicationEvent>[];
    final subscription = events.events.listen((event) {
      if (event is ApplicationEvent) observed.add(event);
    });
    await _tool(events, MockUiAutomation()).execute(const {
      'window_id': windowId,
      'element_id': valueElementId,
      'value': secretValue,
    }, _writeContext());

    expect(observed.map((event) => event.type), [
      'ui.value.started',
      'ui.value.succeeded',
    ]);
    for (final event in observed) {
      expect(jsonEncode(event.data), isNot(contains(secretValue)));
      expect(event.data, isNot(contains('value')));
      expect(event.data['operation'], 'set_value');
    }
    await subscription.cancel();
    await events.close();
  });

  test(
    'failure events sanitize failure messages and submitted value',
    () async {
      final events = EventBus();
      final observed = <ApplicationEvent>[];
      final subscription = events.events.listen((event) {
        if (event is ApplicationEvent) observed.add(event);
      });
      await _tool(
        events,
        MockUiAutomation(
          setValueFailure: const Failure(
            'Provider accidentally echoed $secretValue',
            code: 'ui_set_value_failed',
          ),
        ),
      ).execute(const {
        'window_id': windowId,
        'element_id': valueElementId,
        'value': secretValue,
      }, _writeContext());

      expect(observed.last.type, 'ui.value.failed');
      expect(jsonEncode(observed.last.data), isNot(contains(secretValue)));
      expect(observed.last.data['failure_code'], 'ui_set_value_failed');
      await subscription.cancel();
      await events.close();
    },
  );
}

SetUiElementValueTool _tool(EventBus events, MockUiAutomation automation) =>
    SetUiElementValueTool(
      uiAutomation: automation,
      windowDiscovery: MockWindowDiscovery(),
      events: events,
    );

ToolExecutionContext _writeContext() => ToolExecutionContext(
  authorizer: AllowListPermissionAuthorizer({Permission.write}),
);

String? _failureCode(Result<ToolOutput> result) =>
    result.fold((_) => null, (failure) => failure.code);

