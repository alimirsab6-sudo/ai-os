import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../../core/result.dart';
import 'browser_controller.dart';
import 'cronyx_browser_profile.dart';

final class WindowsWebView2BrowserController implements BrowserController {
  WindowsWebView2BrowserController({Map<String, String>? environment})
    : _environment = environment ?? Platform.environment;

  static Future<void>? _environmentInitialization;

  final Map<String, String> _environment;
  WebviewController _controller = WebviewController();
  final StreamController<BrowserControllerState> _states =
      StreamController<BrowserControllerState>.broadcast(sync: true);
  final List<StreamSubscription<Object?>> _subscriptions = [];

  BrowserControllerState _state = const BrowserControllerState.uninitialized();
  bool _disposing = false;

  @override
  Stream<BrowserControllerState> get states => _states.stream;

  @override
  BrowserControllerState get state => _state;

  @override
  Future<Result<void>> initialize() async {
    if (_disposing) {
      return const Result.failure(
        Failure('Browser session is being disposed.', code: 'browser_disposed'),
      );
    }
    if (_state.isInitialized) return const Result.success(null);
    if (!Platform.isWindows) {
      return const Result.failure(
        Failure(
          'The embedded browser prototype is currently Windows-only.',
          code: 'unsupported_platform',
        ),
      );
    }

    final profileResult = CronyxBrowserProfile.resolvePath(_environment);
    if (profileResult case Failed<String>(:final failure)) {
      return Result.failure(failure);
    }
    final profilePath = (profileResult as Success<String>).value;

    try {
      await Directory(profilePath).create(recursive: true);
      final runtimeVersion = await WebviewController.getWebViewVersion();
      if (runtimeVersion == null) {
        return const Result.failure(
          Failure(
            'Microsoft Edge WebView2 Runtime is not installed.',
            code: 'webview2_runtime_missing',
          ),
        );
      }
      await _initializeEnvironment(profilePath);
      await _controller.initialize();
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await _controller.setDefaultContextMenusEnabled(false);
      _subscribeToPlatformState();
      _setState(
        BrowserControllerState(
          isInitialized: true,
          loadingState: BrowserLoadingState.idle,
          currentUrl: _state.currentUrl,
          title: _state.title,
          canGoBack: _state.canGoBack,
          canGoForward: _state.canGoForward,
        ),
      );
      return const Result.success(null);
    } on Object {
      return const Result.failure(
        Failure(
          'The embedded browser could not be initialized.',
          code: 'browser_initialization_failed',
        ),
      );
    }
  }

  Future<void> _initializeEnvironment(String profilePath) {
    final existing = _environmentInitialization;
    if (existing != null) return existing;
    final initialization = WebviewController.initializeEnvironment(
      userDataPath: profilePath,
    );
    _environmentInitialization = initialization;
    initialization.catchError((Object _) {
      if (identical(_environmentInitialization, initialization)) {
        _environmentInitialization = null;
      }
    });
    return initialization;
  }

  void _subscribeToPlatformState() {
    _subscriptions.add(
      _controller.url.listen((value) {
        _setState(
          BrowserControllerState(
            isInitialized: true,
            loadingState: _state.loadingState,
            currentUrl: Uri.tryParse(value),
            title: _state.title,
            canGoBack: _state.canGoBack,
            canGoForward: _state.canGoForward,
          ),
        );
      }),
    );
    _subscriptions.add(
      _controller.title.listen((value) {
        _setState(
          BrowserControllerState(
            isInitialized: true,
            loadingState: _state.loadingState,
            currentUrl: _state.currentUrl,
            title: value,
            canGoBack: _state.canGoBack,
            canGoForward: _state.canGoForward,
          ),
        );
      }),
    );
    _subscriptions.add(
      _controller.loadingState.listen((value) {
        _setState(
          BrowserControllerState(
            isInitialized: true,
            loadingState: switch (value) {
              LoadingState.loading => BrowserLoadingState.loading,
              LoadingState.navigationCompleted => BrowserLoadingState.completed,
              LoadingState.none => BrowserLoadingState.idle,
            },
            currentUrl: _state.currentUrl,
            title: _state.title,
            canGoBack: _state.canGoBack,
            canGoForward: _state.canGoForward,
          ),
        );
      }),
    );
    _subscriptions.add(
      _controller.historyChanged.listen((value) {
        _setState(
          BrowserControllerState(
            isInitialized: true,
            loadingState: _state.loadingState,
            currentUrl: _state.currentUrl,
            title: _state.title,
            canGoBack: value.canGoBack,
            canGoForward: value.canGoForward,
          ),
        );
      }),
    );
    _subscriptions.add(
      _controller.onLoadError.listen((_) {
        _setState(
          BrowserControllerState(
            isInitialized: true,
            loadingState: BrowserLoadingState.idle,
            currentUrl: _state.currentUrl,
            title: _state.title,
            canGoBack: _state.canGoBack,
            canGoForward: _state.canGoForward,
            navigationFailure: const Failure(
              'The page could not be loaded.',
              code: 'browser_navigation_failed',
            ),
          ),
        );
      }),
    );
  }

  void _setState(BrowserControllerState value) {
    _state = value;
    if (!_states.isClosed) _states.add(value);
  }

  @override
  Future<Result<void>> navigate(Uri url) async {
    final validation = EmbeddedBrowserUrlPolicy.validate(url);
    if (validation case Failed<Uri>(:final failure)) {
      return Result.failure(failure);
    }
    return _performInitialized(
      () => _controller.loadUrl((validation as Success<Uri>).value.toString()),
      failureCode: 'browser_navigation_failed',
    );
  }

  @override
  Future<Result<void>> goBack() => _performInitialized(
    _controller.goBack,
    failureCode: 'browser_history_failed',
  );

  @override
  Future<Result<void>> goForward() => _performInitialized(
    _controller.goForward,
    failureCode: 'browser_history_failed',
  );

  @override
  Future<Result<void>> reload() => _performInitialized(
    _controller.reload,
    failureCode: 'browser_reload_failed',
  );

  Future<Result<void>> _performInitialized(
    Future<void> Function() operation, {
    required String failureCode,
  }) async {
    if (!_state.isInitialized || _disposing) {
      return const Result.failure(
        Failure('Browser is not ready.', code: 'browser_not_ready'),
      );
    }
    try {
      await operation();
      return const Result.success(null);
    } on Object {
      return Result.failure(
        Failure('The browser operation failed.', code: failureCode),
      );
    }
  }

  @override
  Future<Result<Uri?>> getCurrentUrl() async {
    if (!_state.isInitialized || _disposing) {
      return const Result.failure(
        Failure('Browser is not ready.', code: 'browser_not_ready'),
      );
    }
    return Result.success(_state.currentUrl);
  }

  @override
  Future<Result<String?>> getTitle() async {
    if (!_state.isInitialized || _disposing) {
      return const Result.failure(
        Failure('Browser is not ready.', code: 'browser_not_ready'),
      );
    }
    return Result.success(_state.title);
  }

  @override
  Future<Result<void>> dispose() async {
    if (_disposing || !_state.isInitialized) return const Result.success(null);
    _disposing = true;
    try {
      for (final subscription in _subscriptions) {
        await subscription.cancel();
      }
      _subscriptions.clear();
      await _controller.dispose();
      _controller = WebviewController();
      _state = const BrowserControllerState.uninitialized();
      if (!_states.isClosed) _states.add(_state);
      _disposing = false;
      return const Result.success(null);
    } on Object {
      _disposing = false;
      return const Result.failure(
        Failure(
          'The embedded browser could not be disposed cleanly.',
          code: 'browser_disposal_failed',
        ),
      );
    }
  }
}

final class WindowsWebView2Surface extends StatelessWidget {
  const WindowsWebView2Surface({required this.controller, super.key});

  final WindowsWebView2BrowserController controller;

  @override
  Widget build(BuildContext context) => Webview(
    controller._controller,
    permissionRequested: (_, _, _) async => WebviewPermissionDecision.deny,
  );
}

