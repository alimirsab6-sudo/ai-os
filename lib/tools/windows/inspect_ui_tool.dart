import '../../core/events/app_event.dart';
import '../../core/events/event_bus.dart';
import '../../core/result.dart';
import '../../core/security/permission.dart';
import '../tool.dart';
import 'discovery/window_discovery.dart';
import 'ui_automation/ui_automation.dart';

final class InspectUiTool extends AuthorizedTool {
  const InspectUiTool({
    required this.uiAutomation,
    required this.windowDiscovery,
    required this.events,
  });

  final UiAutomation uiAutomation;
  final WindowDiscovery windowDiscovery;
  final EventPublisher events;

  @override
  String get id => 'windows.inspect_ui';

  @override
  String get name => 'Inspect UI';

  @override
  String get description =>
      'Reads a bounded accessible UI hierarchy for a discovered window.';

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema(
    fields: {
      'window_id': ToolInputField(
        type: ToolValueType.string,
        description: 'Runtime ID from current window discovery.',
        required: true,
      ),
      'max_depth': ToolInputField(
        type: ToolValueType.number,
        description: 'Maximum traversal depth.',
        required: true,
      ),
      'max_elements': ToolInputField(
        type: ToolValueType.number,
        description: 'Maximum number of returned elements.',
        required: true,
      ),
    },
  );

  @override
  Set<Permission> get requiredPermissions => const {Permission.read};

  @override
  Future<Result<Map<String, Object?>>> prepare(
    Map<String, Object?> input,
  ) async {
    final windowId = input['window_id'];
    final maxDepth = input['max_depth'];
    final maxElements = input['max_elements'];
    if (windowId is! String ||
        !RegExp(
          r'^windows:window:[0-9a-f]+$',
          caseSensitive: false,
        ).hasMatch(windowId)) {
      return const Result.failure(
        Failure('Invalid runtime window ID.', code: 'invalid_window_id'),
      );
    }
    if (maxDepth is! int ||
        maxDepth < 0 ||
        maxDepth > UiTraversalLimits.maximumDepth) {
      return const Result.failure(
        Failure(
          'max_depth is outside the supported range.',
          code: 'invalid_traversal_limit',
        ),
      );
    }
    if (maxElements is! int ||
        maxElements < 1 ||
        maxElements > UiTraversalLimits.maximumElements) {
      return const Result.failure(
        Failure(
          'max_elements is outside the supported range.',
          code: 'invalid_traversal_limit',
        ),
      );
    }
    return Result.success({
      'window_id': windowId,
      'max_depth': maxDepth,
      'max_elements': maxElements,
    });
  }

  @override
  Future<Result<ToolOutput>> perform(Map<String, Object?> input) async {
    final windowId = input['window_id']! as String;
    final discoveryResult = await windowDiscovery.listWindows();
    if (discoveryResult case Failed(:final failure)) {
      return Result.failure(failure);
    }
    final windows = (discoveryResult as Success).value;
    if (!windows.any((window) => window.id == windowId)) {
      return Result.failure(
        Failure(
          'Window "$windowId" is no longer discoverable.',
          code: 'window_not_found',
        ),
      );
    }

    final result = await uiAutomation.inspectWindow(
      windowId,
      maxDepth: input['max_depth']! as int,
      maxElements: input['max_elements']! as int,
    );
    return result.fold(
      (inspection) => Result.success(
        ToolOutput(
          data: inspection.toMap(),
          summary: 'Inspected ${inspection.elements.length} UI elements.',
        ),
      ),
      Result.failure,
    );
  }

  @override
  void onStarted(Map<String, Object?> input) {
    events.publish(
      ApplicationEvent(
        type: 'ui.inspection.started',
        occurredAt: DateTime.now().toUtc(),
        data: _eventData(input),
      ),
    );
  }

  @override
  void onSucceeded(ToolOutput output) {
    events.publish(
      ApplicationEvent(
        type: 'ui.inspection.succeeded',
        occurredAt: DateTime.now().toUtc(),
        data: {
          'window_id': output.data['window_id'],
          'max_depth': output.data['max_depth'],
          'max_elements': output.data['max_elements'],
          'element_count': output.data['element_count'],
          'was_truncated': output.data['was_truncated'],
        },
      ),
    );
  }

  @override
  void onFailedWithInput(Failure failure, Map<String, Object?> input) {
    events.publish(
      ApplicationEvent(
        type: 'ui.inspection.failed',
        occurredAt: DateTime.now().toUtc(),
        data: {
          ..._eventData(input),
          'failure_code': failure.code,
          'message': failure.message,
        },
      ),
    );
  }

  Map<String, Object?> _eventData(Map<String, Object?> input) => {
    'window_id': input['window_id'],
    'max_depth': input['max_depth'],
    'max_elements': input['max_elements'],
  };
}

