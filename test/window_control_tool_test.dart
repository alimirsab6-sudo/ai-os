import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/events/app_event.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/tool.dart';
import 'package:ai_os/tools/windows/control/window_controller.dart';
import 'package:ai_os/tools/windows/window_control_tools.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/window_controller_fakes.dart';

const windowId = 'windows:window:abc';

void main() {
  for (final operation in WindowOperation.values) {
    test('${operation.name} tool routes a successful operation', () async {
      final events = EventBus();
      final controller = MockWindowController();
      final tool = _toolFor(operation, controller, events);
      final permission = operation == WindowOperation.close
          ? Permission.sensitive
          : Permission.execute;

      final result = await tool.execute(
        const {'window_id': windowId},
        ToolExecutionContext(
          authorizer: AllowListPermissionAuthorizer({permission}),
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(controller.calls.single.operation, operation);
      expect(controller.calls.single.windowId, windowId);
      await events.close();
    });
  }

  test(
    'invalid window ID input is rejected before controller invocation',
    () async {
      final events = EventBus();
      final controller = MockWindowController();
      final tool = ActivateWindowTool(controller: controller, events: events);

      final result = await tool.execute(
        const {'window_id': 'not-a-runtime-id'},
        ToolExecutionContext(
          authorizer: AllowListPermissionAuthorizer({Permission.execute}),
        ),
      );

      expect(
        result.fold((_) => null, (failure) => failure.code),
        'invalid_window_id',
      );
      expect(controller.calls, isEmpty);
      await events.close();
    },
  );

  test('permission denial prevents controller invocation', () async {
    final events = EventBus();
    final controller = MockWindowController();
    final tool = MinimizeWindowTool(controller: controller, events: events);

    final result = await tool.execute(const {
      'window_id': windowId,
    }, ToolExecutionContext(authorizer: AllowListPermissionAuthorizer({})));

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'permission_denied',
    );
    expect(controller.calls, isEmpty);
    await events.close();
  });

  test('close requires sensitive rather than execute permission', () async {
    final events = EventBus();
    final controller = MockWindowController();
    final tool = CloseWindowTool(controller: controller, events: events);

    final result = await tool.execute(
      const {'window_id': windowId},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.execute}),
      ),
    );

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'permission_denied',
    );
    expect(controller.calls, isEmpty);
    await events.close();
  });

  test('controller failure remains a structured tool failure', () async {
    final events = EventBus();
    final controller = MockWindowController(
      failureOperation: WindowOperation.maximize,
    );
    final tool = MaximizeWindowTool(controller: controller, events: events);

    final result = await tool.execute(
      const {'window_id': windowId},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.execute}),
      ),
    );

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'window_control_failed',
    );
    await events.close();
  });

  test('tool emits structured success lifecycle events', () async {
    final events = EventBus();
    final observed = <Map<String, Object?>>[];
    final subscription = events.events.listen((event) {
      if (event is ApplicationEvent) {
        observed.add({'type': event.type, ...event.data});
      }
    });
    final tool = RestoreWindowTool(
      controller: MockWindowController(),
      events: events,
    );

    await tool.execute(
      const {'window_id': windowId},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.execute}),
      ),
    );

    expect(observed.map((event) => event['type']), [
      'window.control.started',
      'window.control.succeeded',
    ]);
    expect(observed.last['window_id'], windowId);
    expect(observed.last['operation'], 'restore');
    expect(observed.last['success'], isTrue);
    await subscription.cancel();
    await events.close();
  });

  test('tool failure event identifies operation and target', () async {
    final events = EventBus();
    final observed = <Map<String, Object?>>[];
    final subscription = events.events.listen((event) {
      if (event is ApplicationEvent) {
        observed.add({'type': event.type, ...event.data});
      }
    });
    final tool = ActivateWindowTool(
      controller: MockWindowController(
        failureOperation: WindowOperation.activate,
      ),
      events: events,
    );

    await tool.execute(
      const {'window_id': windowId},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.execute}),
      ),
    );

    expect(observed.last['type'], 'window.control.failed');
    expect(observed.last['window_id'], windowId);
    expect(observed.last['operation'], 'activate');
    expect(observed.last['success'], isFalse);
    await subscription.cancel();
    await events.close();
  });
}

WindowControlTool _toolFor(
  WindowOperation operation,
  WindowController controller,
  EventBus events,
) => switch (operation) {
  WindowOperation.activate => ActivateWindowTool(
    controller: controller,
    events: events,
  ),
  WindowOperation.minimize => MinimizeWindowTool(
    controller: controller,
    events: events,
  ),
  WindowOperation.maximize => MaximizeWindowTool(
    controller: controller,
    events: events,
  ),
  WindowOperation.restore => RestoreWindowTool(
    controller: controller,
    events: events,
  ),
  WindowOperation.close => CloseWindowTool(
    controller: controller,
    events: events,
  ),
};
