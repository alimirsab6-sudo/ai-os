import '../../browser/browser_context.dart';
import '../../core/events/app_event.dart';
import '../../core/events/event_bus.dart';
import '../../core/result.dart';
import '../../core/security/permission.dart';
import '../tool.dart';
import '../windows/discovery/window_discovery.dart';
import '../windows/discovery/window_info.dart';
import '../windows/ui_automation/ui_automation.dart';

final class InspectBrowserContextTool extends AuthorizedTool {
  const InspectBrowserContextTool({
    required this.windowDiscovery,
    required this.uiAutomation,
    required this.events,
  });

  final WindowDiscovery windowDiscovery;
  final UiAutomation uiAutomation;
  final EventPublisher events;

  @override
  String get id => 'browser.inspect_context';

  @override
  String get name => 'Inspect browser context';

  @override
  String get description =>
      'Reads bounded accessibility metadata from an allow-listed browser window.';

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema(
    fields: {
      'window_id': ToolInputField(
        type: ToolValueType.string,
        description: 'Optional runtime ID of a discovered browser window.',
      ),
      'max_depth': ToolInputField(
        type: ToolValueType.number,
        description: 'Maximum accessibility traversal depth.',
      ),
      'max_elements': ToolInputField(
        type: ToolValueType.number,
        description: 'Maximum number of returned elements.',
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
    if (windowId != null &&
        (windowId is! String ||
            !RegExp(
              r'^windows:window:[0-9a-f]+$',
              caseSensitive: false,
            ).hasMatch(windowId))) {
      return const Result.failure(
        Failure('Invalid runtime window ID.', code: 'invalid_window_id'),
      );
    }

    final maxDepth = input['max_depth'] ?? UiTraversalLimits.defaultMaxDepth;
    final maxElements =
        input['max_elements'] ?? UiTraversalLimits.defaultMaxElements;
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
    final discoveryResult = await windowDiscovery.listWindows();
    if (discoveryResult case Failed<List<WindowInfo>>(:final failure)) {
      return Result.failure(failure);
    }
    final windows = (discoveryResult as Success<List<WindowInfo>>).value;
    final requestedWindowId = input['window_id'] as String?;
    final window = _selectWindow(windows, requestedWindowId);
    if (window == null) {
      return const Result.failure(
        Failure(
          'No eligible browser window was found.',
          code: 'browser_window_not_found',
        ),
      );
    }
    final browser = browserApplicationFor(window);
    if (browser == null) {
      return const Result.failure(
        Failure(
          'The selected window is not an allow-listed browser.',
          code: 'not_browser_window',
        ),
      );
    }

    final maxDepth = input['max_depth']! as int;
    final maxElements = input['max_elements']! as int;
    final inspectionResult = await uiAutomation.inspectWindow(
      window.id,
      maxDepth: maxDepth,
      maxElements: maxElements,
    );
    return inspectionResult.fold((inspection) {
      final boundedElements = inspection.elements
          .where((element) => element.depth <= maxDepth)
          .take(maxElements)
          .map(BrowserContextElement.fromUiElement)
          .toList(growable: false);
      final context = BrowserContext(
        browser: browser,
        windowId: window.id,
        title: window.title,
        elements: boundedElements,
        maxDepth: maxDepth,
        maxElements: maxElements,
        wasTruncated:
            inspection.wasTruncated ||
            boundedElements.length < inspection.elements.length,
      );
      return Result.success(
        ToolOutput(
          data: context.toMap(),
          summary:
              'Inspected ${context.elements.length} elements in ${browser.name}.',
        ),
      );
    }, Result.failure);
  }

  WindowInfo? _selectWindow(
    List<WindowInfo> windows,
    String? requestedWindowId,
  ) {
    if (requestedWindowId != null) {
      for (final window in windows) {
        if (window.id == requestedWindowId && window.isVisible) return window;
      }
      return null;
    }
    for (final window in windows) {
      if (window.isActive &&
          window.isVisible &&
          browserApplicationFor(window) != null) {
        return window;
      }
    }
    return null;
  }

  @override
  void onStarted(Map<String, Object?> input) {
    events.publish(
      ApplicationEvent(
        type: 'browser.context.inspection.started',
        occurredAt: DateTime.now().toUtc(),
        data: _requestEventData(input),
      ),
    );
  }

  @override
  void onSucceeded(ToolOutput output) {
    events.publish(
      ApplicationEvent(
        type: 'browser.context.inspection.succeeded',
        occurredAt: DateTime.now().toUtc(),
        data: {
          'browser': output.data['browser'],
          'window_id': output.data['window_id'],
          'element_count': output.data['element_count'],
          'max_depth': output.data['max_depth'],
          'max_elements': output.data['max_elements'],
          'was_truncated': output.data['was_truncated'],
        },
      ),
    );
  }

  @override
  void onFailedWithInput(Failure failure, Map<String, Object?> input) {
    events.publish(
      ApplicationEvent(
        type: 'browser.context.inspection.failed',
        occurredAt: DateTime.now().toUtc(),
        data: {..._requestEventData(input), 'failure_code': failure.code},
      ),
    );
  }

  Map<String, Object?> _requestEventData(Map<String, Object?> input) => {
    'window_id': input['window_id'],
    'max_depth': input['max_depth'],
    'max_elements': input['max_elements'],
  };
}
