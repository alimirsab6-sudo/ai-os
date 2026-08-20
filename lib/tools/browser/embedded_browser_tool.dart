import 'dart:async';

import '../../browser/embedded/browser_controller.dart';
import '../../core/events/app_event.dart';
import '../../core/events/event_bus.dart';
import '../../core/result.dart';
import '../../core/security/permission.dart';
import '../tool.dart';

enum EmbeddedBrowserOperation {
  initialize('initialize'),
  navigate('navigate'),
  back('back'),
  forward('forward'),
  reload('reload'),
  currentUrl('current_url'),
  title('title'),
  dispose('dispose');

  const EmbeddedBrowserOperation(this.id);

  final String id;

  static EmbeddedBrowserOperation? fromId(String id) {
    for (final operation in values) {
      if (operation.id == id) return operation;
    }
    return null;
  }
}

/// The sole authorized tool boundary for the embedded CronyX browser.
///
/// It accepts a fixed operation enum rather than script, shell, JavaScript, or
/// arbitrary automation input. Page content and profile details are never
/// included in emitted events.
final class EmbeddedBrowserTool extends AuthorizedTool {
  EmbeddedBrowserTool({required this.controller, required this.events});

  final BrowserController controller;
  final EventPublisher events;

  StreamSubscription<BrowserControllerState>? _stateSubscription;
  bool _createdPublished = false;
  bool _readyPublished = false;
  bool _navigationPending = false;
  bool _navigationFailurePublished = false;
  String? _pendingOperation;
  String? _pendingHost;

  @override
  String get id => 'browser.embedded.control';

  @override
  String get name => 'Control CronyX Browser';

  @override
  String get description =>
      'Controls the embedded browser with approved navigation operations.';

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema(
    fields: {
      'operation': ToolInputField(
        type: ToolValueType.string,
        description: 'A supported embedded browser operation.',
        required: true,
      ),
      'url': ToolInputField(
        type: ToolValueType.string,
        description: 'An absolute HTTP or HTTPS URL for navigation.',
      ),
    },
  );

  @override
  Set<Permission> get requiredPermissions => const {Permission.execute};

  @override
  Future<Result<Map<String, Object?>>> prepare(
    Map<String, Object?> input,
  ) async {
    final rawOperation = input['operation'];
    if (rawOperation is! String) return _invalidInput();
    final operation = EmbeddedBrowserOperation.fromId(rawOperation.trim());
    if (operation == null) return _invalidInput();

    if (operation != EmbeddedBrowserOperation.navigate) {
      return Result.success({'operation': operation});
    }

    final rawUrl = input['url'];
    if (rawUrl is! String) return _invalidUrl();
    final parsed = Uri.tryParse(rawUrl.trim());
    if (parsed == null) return _invalidUrl();
    final validated = EmbeddedBrowserUrlPolicy.validate(parsed);
    return validated.fold(
      (url) => Result.success({'operation': operation, 'url': url}),
      (_) => _invalidUrl(),
    );
  }

  @override
  Future<Result<ToolOutput>> perform(Map<String, Object?> input) async {
    final operation = input['operation'];
    if (operation is! EmbeddedBrowserOperation) {
      return const Result.failure(
        Failure('Browser operation is missing.', code: 'invalid_tool_state'),
      );
    }

    if (operation == EmbeddedBrowserOperation.dispose) {
      final result = await controller.dispose();
      if (result case Failed<void>(:final failure)) {
        return Result.failure(failure);
      }
      await _stateSubscription?.cancel();
      _stateSubscription = null;
      _publish('browser.disposed');
      _createdPublished = false;
      _readyPublished = false;
      _navigationPending = false;
      return const Result.success(ToolOutput(data: {'operation': 'dispose'}));
    }

    final initialized = await _ensureInitialized();
    if (initialized case Failed<void>(:final failure)) {
      return Result.failure(failure);
    }

    switch (operation) {
      case EmbeddedBrowserOperation.initialize:
        return const Result.success(
          ToolOutput(
            data: {'operation': 'initialize'},
            summary: 'CronyX Browser is ready.',
          ),
        );
      case EmbeddedBrowserOperation.navigate:
        final url = input['url'];
        if (url is! Uri) {
          return const Result.failure(
            Failure('Validated URL is missing.', code: 'invalid_tool_state'),
          );
        }
        return _performNavigation(
          operation,
          () => controller.navigate(url),
          url,
        );
      case EmbeddedBrowserOperation.back:
        return _performNavigation(operation, controller.goBack);
      case EmbeddedBrowserOperation.forward:
        return _performNavigation(operation, controller.goForward);
      case EmbeddedBrowserOperation.reload:
        return _performNavigation(operation, controller.reload);
      case EmbeddedBrowserOperation.currentUrl:
        final result = await controller.getCurrentUrl();
        return result.fold(
          (url) => Result.success(
            ToolOutput(
              data: {'operation': operation.id, 'url': url?.toString()},
              summary: url == null
                  ? 'No page is open.'
                  : 'Current page is ${url.host}.',
            ),
          ),
          Result.failure,
        );
      case EmbeddedBrowserOperation.title:
        final result = await controller.getTitle();
        return result.fold(
          (title) => Result.success(
            ToolOutput(
              data: {'operation': operation.id, 'title': title},
              summary: title ?? 'The page has no title.',
            ),
          ),
          Result.failure,
        );
      case EmbeddedBrowserOperation.dispose:
        throw StateError('Dispose was handled above.');
    }
  }

  Future<Result<void>> _ensureInitialized() async {
    _stateSubscription ??= controller.states.listen(_handleControllerState);
    if (controller.state.isInitialized) return const Result.success(null);
    if (!_createdPublished) {
      _createdPublished = true;
      _publish('browser.created');
    }
    final result = await controller.initialize();
    if (result.isSuccess && !_readyPublished) {
      _readyPublished = true;
      _publish('browser.ready');
    }
    return result;
  }

  Future<Result<ToolOutput>> _performNavigation(
    EmbeddedBrowserOperation operation,
    Future<Result<void>> Function() action, [
    Uri? url,
  ]) async {
    if (operation == EmbeddedBrowserOperation.back &&
        !controller.state.canGoBack) {
      return const Result.failure(
        Failure(
          'There is no previous browser page.',
          code: 'browser_history_unavailable',
        ),
      );
    }
    if (operation == EmbeddedBrowserOperation.forward &&
        !controller.state.canGoForward) {
      return const Result.failure(
        Failure(
          'There is no next browser page.',
          code: 'browser_history_unavailable',
        ),
      );
    }
    if (operation == EmbeddedBrowserOperation.reload &&
        controller.state.currentUrl == null) {
      return const Result.failure(
        Failure(
          'There is no browser page to reload.',
          code: 'browser_page_unavailable',
        ),
      );
    }
    _navigationPending = true;
    _navigationFailurePublished = false;
    _pendingOperation = operation.id;
    _pendingHost = url?.host ?? controller.state.currentUrl?.host;
    _publish(
      'browser.navigation.started',
      data: {'operation': operation.id, 'host': ?_pendingHost},
    );
    final result = await action();
    return result.fold(
      (_) => Result.success(
        ToolOutput(
          data: {
            'operation': operation.id,
            'host': ?_pendingHost,
            'awaiting_page_load': true,
          },
          summary: operation == EmbeddedBrowserOperation.navigate
              ? '${url!.host} is opening in CronyX Browser.'
              : 'Browser ${operation.id} requested.',
        ),
      ),
      (failure) {
        _navigationPending = false;
        return Result.failure(failure);
      },
    );
  }

  void _handleControllerState(BrowserControllerState state) {
    if (!_navigationPending) return;
    final failure = state.navigationFailure;
    if (failure != null) {
      _navigationPending = false;
      _navigationFailurePublished = true;
      _publish(
        'browser.navigation.failed',
        data: {
          'operation': _pendingOperation,
          'host': ?_pendingHost,
          'failure_code': failure.code,
        },
      );
      return;
    }
    if (state.loadingState != BrowserLoadingState.completed) return;
    _navigationPending = false;
    final data = <String, Object?>{
      'operation': _pendingOperation,
      'host': state.currentUrl?.host ?? _pendingHost,
    };
    _publish('browser.navigation.completed', data: data);
    _publish('browser.page.loaded', data: data);
  }

  @override
  void onStarted(Map<String, Object?> input) {
    final operation = input['operation'];
    final rawUrl = input['url'];
    final host = rawUrl is String ? Uri.tryParse(rawUrl)?.host : null;
    _publish('tool.started', data: {'tool_id': id, 'operation': operation});
    if (operation == EmbeddedBrowserOperation.navigate.id ||
        operation == EmbeddedBrowserOperation.back.id ||
        operation == EmbeddedBrowserOperation.forward.id ||
        operation == EmbeddedBrowserOperation.reload.id) {
      _publish(
        'browser.navigation.requested',
        data: {'operation': operation, 'host': ?host},
      );
    }
  }

  @override
  void onSucceeded(ToolOutput output) {
    _publish(
      'tool.succeeded',
      data: {
        'tool_id': id,
        'operation': output.data['operation'],
        'host': ?output.data['host'],
      },
    );
  }

  @override
  void onFailedWithInput(Failure failure, Map<String, Object?> input) {
    _publish(
      'tool.failed',
      data: {'tool_id': id, 'failure_code': failure.code},
    );
    final operation = input['operation'];
    if (!_navigationFailurePublished &&
        (operation == EmbeddedBrowserOperation.navigate.id ||
            operation == EmbeddedBrowserOperation.back.id ||
            operation == EmbeddedBrowserOperation.forward.id ||
            operation == EmbeddedBrowserOperation.reload.id)) {
      final rawUrl = input['url'];
      final host = rawUrl is String ? Uri.tryParse(rawUrl)?.host : null;
      _publish(
        'browser.navigation.failed',
        data: {
          'operation': operation,
          'host': ?host,
          'failure_code': failure.code,
        },
      );
    }
    _navigationPending = false;
    _navigationFailurePublished = false;
  }

  void _publish(String type, {Map<String, Object?> data = const {}}) {
    events.publish(
      ApplicationEvent(
        type: type,
        occurredAt: DateTime.now().toUtc(),
        data: data,
      ),
    );
  }

  Result<Map<String, Object?>> _invalidInput() => const Result.failure(
    Failure(
      'A supported browser operation is required.',
      code: 'invalid_tool_input',
    ),
  );

  Result<Map<String, Object?>> _invalidUrl() => const Result.failure(
    Failure(
      'Only an absolute HTTP or HTTPS web address can be opened.',
      code: 'invalid_url',
    ),
  );
}

