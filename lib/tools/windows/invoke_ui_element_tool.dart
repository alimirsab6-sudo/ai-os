import '../../core/events/app_event.dart';
import '../../core/events/event_bus.dart';
import '../../core/result.dart';
import '../../core/security/permission.dart';
import '../tool.dart';
import 'discovery/window_discovery.dart';
import 'ui_automation/ui_automation.dart';
import 'ui_automation/ui_element.dart';

final class InvokeUiElementTool extends AuthorizedTool {
  const InvokeUiElementTool({
    required this.uiAutomation,
    required this.windowDiscovery,
    required this.events,
  });

  final UiAutomation uiAutomation;
  final WindowDiscovery windowDiscovery;
  final EventPublisher events;

  @override
  String get id => 'windows.invoke_ui_element';

  @override
  String get name => 'Invoke UI element';

  @override
  String get description =>
      'Invokes a freshly discovered UI element that supports Invoke.';

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema(
    fields: {
      'window_id': ToolInputField(
        type: ToolValueType.string,
        description: 'Current discovered top-level window runtime ID.',
        required: true,
      ),
      'element_id': ToolInputField(
        type: ToolValueType.string,
        description: 'Opaque element ID from the latest UI inspection.',
        required: true,
      ),
    },
  );

  @override
  Set<Permission> get requiredPermissions => const {Permission.execute};

  @override
  Future<Result<Map<String, Object?>>> prepare(
    Map<String, Object?> input,
  ) async {
    final windowId = input['window_id'];
    final elementId = input['element_id'];
    if (windowId is! String || windowId.isEmpty) {
      return const Result.failure(
        Failure('window_id is required.', code: 'missing_window_id'),
      );
    }
    if (!RegExp(
      r'^windows:window:[0-9a-f]+$',
      caseSensitive: false,
    ).hasMatch(windowId)) {
      return const Result.failure(
        Failure('Invalid runtime window ID.', code: 'invalid_window_id'),
      );
    }
    if (elementId is! String || elementId.isEmpty) {
      return const Result.failure(
        Failure('element_id is required.', code: 'missing_element_id'),
      );
    }
    if (!RegExp(r'^uia:[0-9a-f]+:\d+$').hasMatch(elementId)) {
      return const Result.failure(
        Failure('Invalid opaque UI element ID.', code: 'invalid_element_id'),
      );
    }
    return Result.success({'window_id': windowId, 'element_id': elementId});
  }

  @override
  Future<Result<ToolOutput>> perform(Map<String, Object?> input) async {
    final windowId = input['window_id']! as String;
    final elementId = input['element_id']! as String;
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

    final elementResult = await uiAutomation.getElement(elementId);
    if (elementResult case Failed<UiElement>(:final failure)) {
      return Result.failure(failure);
    }
    final element = (elementResult as Success<UiElement>).value;
    if (!element.supportedPatterns.contains(UiPattern.invoke)) {
      return const Result.failure(
        Failure(
          'The UI element does not support the Invoke pattern.',
          code: 'invoke_not_supported',
        ),
      );
    }

    final invokeResult = await uiAutomation.invoke(windowId, elementId);
    return invokeResult.fold(
      (receipt) => Result.success(
        ToolOutput(
          data: {
            'window_id': receipt.windowId,
            'element_id': receipt.elementId,
          },
          summary: 'UI element invoked.',
        ),
      ),
      Result.failure,
    );
  }

  @override
  void onStarted(Map<String, Object?> input) {
    events.publish(
      ApplicationEvent(
        type: 'ui.invoke.started',
        occurredAt: DateTime.now().toUtc(),
        data: _eventData(input),
      ),
    );
  }

  @override
  void onSucceeded(ToolOutput output) {
    events.publish(
      ApplicationEvent(
        type: 'ui.invoke.succeeded',
        occurredAt: DateTime.now().toUtc(),
        data: {..._eventData(output.data), 'success': true},
      ),
    );
  }

  @override
  void onFailedWithInput(Failure failure, Map<String, Object?> input) {
    events.publish(
      ApplicationEvent(
        type: 'ui.invoke.failed',
        occurredAt: DateTime.now().toUtc(),
        data: {
          ..._eventData(input),
          'success': false,
          'failure_code': failure.code,
          'message': failure.message,
        },
      ),
    );
  }

  Map<String, Object?> _eventData(Map<String, Object?> input) => {
    'window_id': input['window_id'],
    'element_id': input['element_id'],
  };
}

