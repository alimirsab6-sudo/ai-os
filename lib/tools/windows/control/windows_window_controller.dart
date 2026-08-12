import 'dart:ffi';
import 'dart:io';

import '../../../core/result.dart';
import '../discovery/window_discovery.dart';
import 'window_controller.dart';

typedef _IsWindowNative = Int32 Function(IntPtr window);
typedef _IsWindowDart = int Function(int window);
typedef _SetForegroundWindowNative = Int32 Function(IntPtr window);
typedef _SetForegroundWindowDart = int Function(int window);
typedef _ShowWindowNative = Int32 Function(IntPtr window, Int32 command);
typedef _ShowWindowDart = int Function(int window, int command);
typedef _PostMessageNative =
    Int32 Function(IntPtr window, Uint32 message, IntPtr wParam, IntPtr lParam);
typedef _PostMessageDart =
    int Function(int window, int message, int wParam, int lParam);

const int _showMaximized = 3;
const int _showMinimized = 6;
const int _restore = 9;
const int _closeMessage = 0x0010;

/// Controls only IDs that still appear in the current discovery snapshot.
final class WindowsWindowController implements WindowController {
  WindowsWindowController({required this.discovery});

  final WindowDiscovery discovery;
  _WindowControlApi? _apiInstance;

  _WindowControlApi get _api => _apiInstance ??= _WindowControlApi();

  @override
  Future<Result<WindowControlReceipt>> activate(String windowId) =>
      _perform(windowId, WindowOperation.activate);

  @override
  Future<Result<WindowControlReceipt>> minimize(String windowId) =>
      _perform(windowId, WindowOperation.minimize);

  @override
  Future<Result<WindowControlReceipt>> maximize(String windowId) =>
      _perform(windowId, WindowOperation.maximize);

  @override
  Future<Result<WindowControlReceipt>> restore(String windowId) =>
      _perform(windowId, WindowOperation.restore);

  @override
  Future<Result<WindowControlReceipt>> close(String windowId) =>
      _perform(windowId, WindowOperation.close);

  Future<Result<WindowControlReceipt>> _perform(
    String windowId,
    WindowOperation operation,
  ) async {
    if (!Platform.isWindows) {
      return const Result.failure(
        Failure(
          'Window control is currently supported only on Windows.',
          code: 'unsupported_platform',
        ),
      );
    }

    final handleResult = await _resolveCurrentHandle(windowId);
    if (handleResult case Failed<int>(:final failure)) {
      return Result.failure(failure);
    }
    final handle = (handleResult as Success<int>).value;

    try {
      final succeeded = switch (operation) {
        WindowOperation.activate => _api.setForegroundWindow(handle) != 0,
        WindowOperation.minimize => _showWindow(handle, _showMinimized),
        WindowOperation.maximize => _showWindow(handle, _showMaximized),
        WindowOperation.restore => _showWindow(handle, _restore),
        WindowOperation.close =>
          _api.postMessage(handle, _closeMessage, 0, 0) != 0,
      };
      if (!succeeded) {
        return Result.failure(
          Failure(
            'Windows rejected the ${operation.name} operation.',
            code: 'window_control_failed',
          ),
        );
      }
      return Result.success(
        WindowControlReceipt(windowId: windowId, operation: operation),
      );
    } on Object catch (error) {
      return Result.failure(
        Failure(
          'The ${operation.name} operation failed: $error',
          code: 'window_control_failed',
        ),
      );
    }
  }

  Future<Result<int>> _resolveCurrentHandle(String windowId) async {
    final match = RegExp(
      r'^windows:window:([0-9a-f]+)$',
      caseSensitive: false,
    ).firstMatch(windowId);
    if (match == null) {
      return const Result.failure(
        Failure('Invalid runtime window ID.', code: 'invalid_window_id'),
      );
    }

    final discoveryResult = await discovery.listWindows();
    if (discoveryResult case Failed(:final failure)) {
      return Result.failure(failure);
    }
    final windows = (discoveryResult as Success).value;
    final isCurrentlyDiscoverable = windows.any(
      (window) => window.id == windowId,
    );
    if (!isCurrentlyDiscoverable) {
      return Result.failure(
        Failure(
          'Window "$windowId" is no longer discoverable.',
          code: 'window_not_found',
        ),
      );
    }

    final handle = int.parse(match.group(1)!, radix: 16);
    if (_api.isWindow(handle) == 0) {
      return Result.failure(
        Failure(
          'Window "$windowId" no longer exists.',
          code: 'window_not_found',
        ),
      );
    }
    return Result.success(handle);
  }

  bool _showWindow(int handle, int command) {
    _api.showWindow(handle, command);
    return _api.isWindow(handle) != 0;
  }
}

final class _WindowControlApi {
  _WindowControlApi() {
    final user32 = DynamicLibrary.open('user32.dll');
    isWindow = user32.lookupFunction<_IsWindowNative, _IsWindowDart>(
      'IsWindow',
    );
    setForegroundWindow = user32
        .lookupFunction<_SetForegroundWindowNative, _SetForegroundWindowDart>(
          'SetForegroundWindow',
        );
    showWindow = user32.lookupFunction<_ShowWindowNative, _ShowWindowDart>(
      'ShowWindow',
    );
    postMessage = user32.lookupFunction<_PostMessageNative, _PostMessageDart>(
      'PostMessageW',
    );
  }

  late final _IsWindowDart isWindow;
  late final _SetForegroundWindowDart setForegroundWindow;
  late final _ShowWindowDart showWindow;
  late final _PostMessageDart postMessage;
}
