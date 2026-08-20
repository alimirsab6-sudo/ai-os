import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/tool.dart';
import 'package:ai_os/tools/windows/launch_application_tool.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pc_agent_fakes.dart';

void main() {
  test('rejects missing or invalid application ID input', () async {
    final events = EventBus();
    final launcher = MockApplicationLauncher();
    final tool = LaunchApplicationTool(
      registry: createChromeRegistry(),
      launcher: launcher,
      events: events,
    );

    final result = await tool.execute(
      const {},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.execute}),
      ),
    );

    expect(result.isFailure, isTrue);
    expect(
      result.fold((_) => null, (failure) => failure.code),
      'invalid_tool_input',
    );
    expect(launcher.launchCount, 0);
    await events.close();
  });

  test('permission denial prevents launcher invocation', () async {
    final events = EventBus();
    final launcher = MockApplicationLauncher();
    final tool = LaunchApplicationTool(
      registry: createChromeRegistry(),
      launcher: launcher,
      events: events,
    );

    final result = await tool.execute(const {
      'application_id': 'chrome',
    }, ToolExecutionContext(authorizer: AllowListPermissionAuthorizer({})));

    expect(result.isFailure, isTrue);
    expect(
      result.fold((_) => null, (failure) => failure.code),
      'permission_denied',
    );
    expect(launcher.launchCount, 0);
    await events.close();
  });

  test('successful mock launch returns structured output', () async {
    final events = EventBus();
    final launcher = MockApplicationLauncher();
    final tool = LaunchApplicationTool(
      registry: createChromeRegistry(),
      launcher: launcher,
      events: events,
    );

    final result = await tool.execute(
      const {'application_id': 'chrome'},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.execute}),
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(
      result.fold((value) => value.data['application_id'], (_) => null),
      'chrome',
    );
    expect(launcher.launchCount, 1);
    await events.close();
  });

  test(
    'successfully launches every registered application by stable ID',
    () async {
      final events = EventBus();
      final launcher = MockApplicationLauncher();
      final tool = LaunchApplicationTool(
        registry: createApplicationRegistry(),
        launcher: launcher,
        events: events,
      );
      const applicationIds = [
        'chrome',
        'edge',
        'notepad',
        'calculator',
        'file_explorer',
        'settings',
        'task_manager',
      ];

      for (final applicationId in applicationIds) {
        final result = await tool.execute(
          {'application_id': applicationId},
          ToolExecutionContext(
            authorizer: AllowListPermissionAuthorizer({Permission.execute}),
          ),
        );
        expect(result.isSuccess, isTrue, reason: applicationId);
        expect(launcher.launchedApplication?.descriptor.id, applicationId);
      }

      expect(launcher.launchCount, applicationIds.length);
      await events.close();
    },
  );

  test('launcher failure is returned without a success event', () async {
    final events = EventBus();
    final eventTypes = <String>[];
    final subscription = events.events.listen(
      (event) => eventTypes.add(event.type),
    );
    final tool = LaunchApplicationTool(
      registry: createApplicationRegistry(),
      launcher: MockApplicationLauncher(shouldSucceed: false),
      events: events,
    );

    final result = await tool.execute(
      const {'application_id': 'notepad'},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.execute}),
      ),
    );

    expect(result.isFailure, isTrue);
    expect(eventTypes, ['tool.started', 'tool.failed']);
    await subscription.cancel();
    await events.close();
  });
}

