import '../../../core/result.dart';

enum WindowOperation { activate, minimize, maximize, restore, close }

final class WindowControlReceipt {
  const WindowControlReceipt({required this.windowId, required this.operation});

  final String windowId;
  final WindowOperation operation;
}

/// Platform-neutral control boundary for an already discovered top-level window.
abstract interface class WindowController {
  Future<Result<WindowControlReceipt>> activate(String windowId);
  Future<Result<WindowControlReceipt>> minimize(String windowId);
  Future<Result<WindowControlReceipt>> maximize(String windowId);
  Future<Result<WindowControlReceipt>> restore(String windowId);
  Future<Result<WindowControlReceipt>> close(String windowId);
}
