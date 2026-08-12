import '../../core/events/app_event.dart';
import '../../core/events/event_bus.dart';
import '../../core/result.dart';
import '../../core/security/permission.dart';
import '../tool.dart';
import 'discovery/window_discovery.dart';

abstract base class WindowDiscoveryTool extends AuthorizedTool {
  const WindowDiscoveryTool({
    required this.discovery,
    required this.events,
    required this.operation,
  });

  final WindowDiscovery discovery;
  final EventPublisher events;
  final String operation;

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema();

  @override
  Set<Permission> get requiredPermissions => const {Permission.read};

  @override
  void onStarted(Map<String, Object?> input) {
    events.publish(
      ApplicationEvent(
        type: 'window.discovery.started',
        occurredAt: DateTime.now().toUtc(),
        data: {'tool_id': id, 'operation': operation},
      ),
    );
  }

  @override
  void onSucceeded(ToolOutput output) {
    events.publish(
      ApplicationEvent(
        type: 'window.discovery.succeeded',
        occurredAt: DateTime.now().toUtc(),
        data: {'tool_id': id, 'operation': operation, ...output.data},
      ),
    );
  }

  @override
  void onFailed(Failure failure) {
    events.publish(
      ApplicationEvent(
        type: 'window.discovery.failed',
        occurredAt: DateTime.now().toUtc(),
        data: {
          'tool_id': id,
          'operation': operation,
          'failure_code': failure.code,
          'message': failure.message,
        },
      ),
    );
  }
}

final class ListWindowsTool extends WindowDiscoveryTool {
  const ListWindowsTool({required super.discovery, required super.events})
    : super(operation: 'list_windows');

  @override
  String get id => 'windows.list_windows';

  @override
  String get name => 'List windows';

  @override
  String get description =>
      'Lists visible top-level windows without interacting with them.';

  @override
  Future<Result<ToolOutput>> perform(Map<String, Object?> input) async {
    final result = await discovery.listWindows();
    return result.fold(
      (windows) => Result.success(
        ToolOutput(
          data: {
            'windows': windows.map((window) => window.toMap()).toList(),
            'window_count': windows.length,
          },
          summary: 'Discovered ${windows.length} visible windows.',
        ),
      ),
      Result.failure,
    );
  }
}

final class GetActiveWindowTool extends WindowDiscoveryTool {
  const GetActiveWindowTool({required super.discovery, required super.events})
    : super(operation: 'get_active_window');

  @override
  String get id => 'windows.get_active_window';

  @override
  String get name => 'Get active window';

  @override
  String get description =>
      'Gets the currently focused top-level window without interacting with it.';

  @override
  Future<Result<ToolOutput>> perform(Map<String, Object?> input) async {
    final result = await discovery.getActiveWindow();
    return result.fold(
      (window) => Result.success(
        ToolOutput(
          data: {'window': window?.toMap()},
          summary: window == null
              ? 'No active window was found.'
              : 'Active window discovered.',
        ),
      ),
      Result.failure,
    );
  }
}
