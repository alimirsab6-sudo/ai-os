import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/tool.dart';
import 'package:ai_os/tools/windows/discovery/window_info.dart';
import 'package:ai_os/tools/windows/window_discovery_tools.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/window_discovery_fakes.dart';

void main() {
  test('mock discovery returns configured desktop state', () async {
    final discovery = MockWindowDiscovery();

    final result = await discovery.listWindows();

    expect(
      result.fold((windows) => windows.single.title, (_) => null),
      'Chrome - Example',
    );
    expect(discovery.listCallCount, 1);
  });

  test('ListWindowsTool returns structured windows', () async {
    final events = EventBus();
    final discovery = MockWindowDiscovery();
    final tool = ListWindowsTool(discovery: discovery, events: events);

    final result = await tool.execute(
      const {},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.read}),
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(
      result.fold((output) => output.data['window_count'], (_) => null),
      1,
    );
    await events.close();
  });

  test('ListWindowsTool succeeds with an empty window list', () async {
    final events = EventBus();
    final discovery = MockWindowDiscovery(
      listResult: const Result.success(<WindowInfo>[]),
    );
    final tool = ListWindowsTool(discovery: discovery, events: events);

    final result = await tool.execute(
      const {},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.read}),
      ),
    );

    expect(
      result.fold((output) => output.data['windows'], (_) => null),
      isEmpty,
    );
    await events.close();
  });

  test('read permission denial prevents discovery', () async {
    final events = EventBus();
    final discovery = MockWindowDiscovery();
    final tool = ListWindowsTool(discovery: discovery, events: events);

    final result = await tool.execute(
      const {},
      ToolExecutionContext(authorizer: AllowListPermissionAuthorizer({})),
    );

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'permission_denied',
    );
    expect(discovery.listCallCount, 0);
    await events.close();
  });

  test('discovery failure is returned without throwing', () async {
    final events = EventBus();
    final discovery = MockWindowDiscovery(
      listResult: const Result.failure(
        Failure('Unavailable.', code: 'discovery_failed'),
      ),
    );
    final tool = ListWindowsTool(discovery: discovery, events: events);

    final result = await tool.execute(
      const {},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.read}),
      ),
    );

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'discovery_failed',
    );
    await events.close();
  });

  test('GetActiveWindowTool returns the active window when present', () async {
    final events = EventBus();
    final discovery = MockWindowDiscovery();
    final tool = GetActiveWindowTool(discovery: discovery, events: events);

    final result = await tool.execute(
      const {},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.read}),
      ),
    );

    expect(
      result.fold(
        (output) => (output.data['window'] as Map<String, Object?>)['title'],
        (_) => null,
      ),
      'Chrome - Example',
    );
    expect(discovery.activeCallCount, 1);
    await events.close();
  });
}

