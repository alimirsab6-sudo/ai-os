import '../../core/events/app_event.dart';
import '../../core/events/event_bus.dart';
import '../../core/result.dart';
import '../../core/security/permission.dart';
import '../tool.dart';
import 'control/window_controller.dart';

abstract base class WindowControlTool extends AuthorizedTool {
  const WindowControlTool({
    required this.controller,
    required this.events,
    required this.operation,
  });

  final WindowController controller;
  final EventPublisher events;
  final WindowOperation operation;

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema(
    fields: {
      'window_id': ToolInputField(
        type: ToolValueType.string,
        description: 'Runtime ID from the current window discovery snapshot.',
        required: true,
      ),
    },
  );

  @override
  Set<Permission> get requiredPermissions => operation == WindowOperation.close
      ? const {Permission.sensitive}
      : const {Permission.execute};

  @override
  Future<Result<Map<String, Object?>>> prepare(
    Map<String, Object?> input,
  ) async {
    final windowId = input['window_id'];
    if (windowId is! String || windowId.trim().isEmpty) {
      return const Result.failure(
        Failure(
          '"window_id" must be a non-empty runtime window ID.',
          code: 'invalid_tool_input',
        ),
      );
    }
    final normalizedId = windowId.trim();
    if (!RegExp(
      r'^windows:window:[0-9a-f]+$',
      caseSensitive: false,
    ).hasMatch(normalizedId)) {
      return const Result.failure(
        Failure('Invalid runtime window ID.', code: 'invalid_window_id'),
      );
    }
    return Result.success({'window_id': normalizedId});
  }

  @override
  Future<Result<ToolOutput>> perform(Map<String, Object?> input) async {
    final windowId = input['window_id']! as String;
    final result = switch (operation) {
      WindowOperation.activate => controller.activate(windowId),
      WindowOperation.minimize => controller.minimize(windowId),
      WindowOperation.maximize => controller.maximize(windowId),
      WindowOperation.restore => controller.restore(windowId),
      WindowOperation.close => controller.close(windowId),
    };
    final receiptResult = await result;
    return receiptResult.fold(
      (receipt) => Result.success(
        ToolOutput(
          data: {
            'window_id': receipt.windowId,
            'operation': receipt.operation.name,
          },
          summary: receipt.operation == WindowOperation.close
              ? 'Window close requested.'
              : 'Window ${receipt.operation.name} succeeded.',
        ),
      ),
      Result.failure,
    );
  }

  @override
  void onStarted(Map<String, Object?> input) {
    events.publish(
      ApplicationEvent(
        type: 'window.control.started',
        occurredAt: DateTime.now().toUtc(),
        data: {
          'tool_id': id,
          'operation': operation.name,
          'window_id': input['window_id'],
        },
      ),
    );
  }

  @override
  void onSucceeded(ToolOutput output) {
    events.publish(
      ApplicationEvent(
        type: 'window.control.succeeded',
        occurredAt: DateTime.now().toUtc(),
        data: {'tool_id': id, ...output.data, 'success': true},
      ),
    );
  }

  @override
  void onFailedWithInput(Failure failure, Map<String, Object?> input) {
    events.publish(
      ApplicationEvent(
        type: 'window.control.failed',
        occurredAt: DateTime.now().toUtc(),
        data: {
          'tool_id': id,
          'operation': operation.name,
          'window_id': input['window_id'],
          'failure_code': failure.code,
          'message': failure.message,
          'success': false,
        },
      ),
    );
  }
}

final class ActivateWindowTool extends WindowControlTool {
  const ActivateWindowTool({required super.controller, required super.events})
    : super(operation: WindowOperation.activate);

  @override
  String get id => 'windows.activate_window';
  @override
  String get name => 'Activate window';
  @override
  String get description => 'Brings a discovered top-level window forward.';
}

final class MinimizeWindowTool extends WindowControlTool {
  const MinimizeWindowTool({required super.controller, required super.events})
    : super(operation: WindowOperation.minimize);

  @override
  String get id => 'windows.minimize_window';
  @override
  String get name => 'Minimize window';
  @override
  String get description => 'Minimizes a discovered top-level window.';
}

final class MaximizeWindowTool extends WindowControlTool {
  const MaximizeWindowTool({required super.controller, required super.events})
    : super(operation: WindowOperation.maximize);

  @override
  String get id => 'windows.maximize_window';
  @override
  String get name => 'Maximize window';
  @override
  String get description => 'Maximizes a discovered top-level window.';
}

final class RestoreWindowTool extends WindowControlTool {
  const RestoreWindowTool({required super.controller, required super.events})
    : super(operation: WindowOperation.restore);

  @override
  String get id => 'windows.restore_window';
  @override
  String get name => 'Restore window';
  @override
  String get description => 'Restores a discovered top-level window.';
}

final class CloseWindowTool extends WindowControlTool {
  const CloseWindowTool({required super.controller, required super.events})
    : super(operation: WindowOperation.close);

  @override
  String get id => 'windows.close_window';
  @override
  String get name => 'Close window';
  @override
  String get description =>
      'Requests that a discovered top-level window close normally.';
}
