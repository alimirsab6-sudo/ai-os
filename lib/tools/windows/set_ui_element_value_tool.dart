import '../../core/events/app_event.dart';
import '../../core/events/event_bus.dart';
import '../../core/result.dart';
import '../../core/security/permission.dart';
import '../tool.dart';
import 'discovery/window_discovery.dart';
import 'ui_automation/ui_automation.dart';
import 'ui_automation/ui_element.dart';

final class SetUiElementValueTool extends AuthorizedTool {
  const SetUiElementValueTool({
    required this.uiAutomation,
    required this.windowDiscovery,
    required this.events,
  });

  final UiAutomation uiAutomation;
  final WindowDiscovery windowDiscovery;
  final EventPublisher events;

  @override
  String get id => 'windows.set_ui_element_value';

  @override
  String get name => 'Set UI element value';

  @override
  String get description =>
      'Sets explicitly supplied text on a freshly discovered writable Value '
      'element.';

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
      'value': ToolInputField(
        type: ToolValueType.string,
        description: 'Explicit replacement text. Never included in events.',
        required: true,
      ),
    },
  );

  @override
  Set<Permission> get requiredPermissions => const {Permission.write};

  @override
  Future<Result<Map<String, Object?>>> prepare(
    Map<String, Object?> input,
  ) async {
    final windowId = input['window_id'];
    final elementId = input['element_id'];
    final value = input['value'];
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
    if (value is! String || value.isEmpty) {
      return const Result.failure(
        Failure('A non-empty value is required.', code: 'missing_value'),
      );
    }
    if (value.length > UiValueLimits.maximumCodeUnits) {
      return const Result.failure(
        Failure(
          'The supplied value exceeds the supported size limit.',
          code: 'value_too_large',
        ),
      );
    }
    return Result.success({
      'window_id': windowId,
      'element_id': elementId,
      'value': value,
    });
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
    if (!element.supportedPatterns.contains(UiPattern.value)) {
      return const Result.failure(
        Failure(
          'The UI element does not support the Value pattern.',
          code: 'value_not_supported',
        ),
      );
    }
    if (element.isValueReadOnly == true) {
      return const Result.failure(
        Failure('The UI element is read-only.', code: 'value_read_only'),
      );
    }

    final result = await uiAutomation.setValue(
      windowId,
      elementId,
      input['value']! as String,
    );
    return result.fold(
      (receipt) => Result.success(
        ToolOutput(
          data: {
            'window_id': receipt.windowId,
            'element_id': receipt.elementId,
          },
          summary: 'UI element value set.',
        ),
      ),
      (failure) => Result.failure(
        Failure(
          'UI Automation SetValue operation failed.',
          code: failure.code ?? 'ui_set_value_failed',
        ),
      ),
    );
  }

  @override
  void onStarted(Map<String, Object?> input) {
    events.publish(
      ApplicationEvent(
        type: 'ui.value.started',
        occurredAt: DateTime.now().toUtc(),
        data: _eventData(input),
      ),
    );
  }

  @override
  void onSucceeded(ToolOutput output) {
    events.publish(
      ApplicationEvent(
        type: 'ui.value.succeeded',
        occurredAt: DateTime.now().toUtc(),
        data: {..._eventData(output.data), 'success': true},
      ),
    );
  }

  @override
  void onFailedWithInput(Failure failure, Map<String, Object?> input) {
    events.publish(
      ApplicationEvent(
        type: 'ui.value.failed',
        occurredAt: DateTime.now().toUtc(),
        data: {
          ..._eventData(input),
          'success': false,
          'failure_code': failure.code,
          'message': 'SetValue operation failed.',
        },
      ),
    );
  }

  Map<String, Object?> _eventData(Map<String, Object?> input) => {
    'operation': 'set_value',
    'window_id': input['window_id'],
    'element_id': input['element_id'],
  };
}
