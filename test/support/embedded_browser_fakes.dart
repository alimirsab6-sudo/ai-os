import 'dart:async';

import 'package:ai_os/browser/embedded/browser_controller.dart';
import 'package:ai_os/core/result.dart';

final class FakeBrowserController implements BrowserController {
  final StreamController<BrowserControllerState> _states =
      StreamController<BrowserControllerState>.broadcast(sync: true);

  BrowserControllerState _state = const BrowserControllerState.uninitialized();
  final List<String> operations = [];
  bool failInitialization = false;
  bool failNavigation = false;

  @override
  Stream<BrowserControllerState> get states => _states.stream;

  @override
  BrowserControllerState get state => _state;

  void emit(BrowserControllerState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  @override
  Future<Result<void>> initialize() async {
    operations.add('initialize');
    if (failInitialization) {
      return const Result.failure(
        Failure(
          'Initialization failed.',
          code: 'browser_initialization_failed',
        ),
      );
    }
    emit(
      const BrowserControllerState(
        isInitialized: true,
        loadingState: BrowserLoadingState.idle,
      ),
    );
    return const Result.success(null);
  }

  @override
  Future<Result<void>> navigate(Uri url) async {
    operations.add('navigate:${url.toString()}');
    if (failNavigation) {
      return const Result.failure(
        Failure('Navigation failed.', code: 'browser_navigation_failed'),
      );
    }
    emit(
      BrowserControllerState(
        isInitialized: true,
        loadingState: BrowserLoadingState.loading,
        currentUrl: url,
        canGoBack: true,
      ),
    );
    return const Result.success(null);
  }

  void completeNavigation({String title = 'Example'}) {
    emit(
      BrowserControllerState(
        isInitialized: true,
        loadingState: BrowserLoadingState.completed,
        currentUrl: _state.currentUrl,
        title: title,
        canGoBack: _state.canGoBack,
        canGoForward: _state.canGoForward,
      ),
    );
  }

  void failCurrentNavigation() {
    emit(
      BrowserControllerState(
        isInitialized: true,
        loadingState: BrowserLoadingState.idle,
        currentUrl: _state.currentUrl,
        navigationFailure: const Failure(
          'Page failed.',
          code: 'browser_navigation_failed',
        ),
      ),
    );
  }

  @override
  Future<Result<void>> goBack() async {
    operations.add('back');
    emit(
      BrowserControllerState(
        isInitialized: true,
        loadingState: BrowserLoadingState.loading,
        currentUrl: _state.currentUrl,
        canGoForward: true,
      ),
    );
    return const Result.success(null);
  }

  @override
  Future<Result<void>> goForward() async {
    operations.add('forward');
    emit(
      BrowserControllerState(
        isInitialized: true,
        loadingState: BrowserLoadingState.loading,
        currentUrl: _state.currentUrl,
        canGoBack: true,
      ),
    );
    return const Result.success(null);
  }

  @override
  Future<Result<void>> reload() async {
    operations.add('reload');
    emit(
      BrowserControllerState(
        isInitialized: true,
        loadingState: BrowserLoadingState.loading,
        currentUrl: _state.currentUrl,
      ),
    );
    return const Result.success(null);
  }

  @override
  Future<Result<Uri?>> getCurrentUrl() async =>
      Result.success(_state.currentUrl);

  @override
  Future<Result<String?>> getTitle() async => Result.success(_state.title);

  @override
  Future<Result<void>> dispose() async {
    if (!_state.isInitialized) return const Result.success(null);
    operations.add('dispose');
    emit(const BrowserControllerState.uninitialized());
    return const Result.success(null);
  }

  Future<void> close() async {
    await _states.close();
  }
}

