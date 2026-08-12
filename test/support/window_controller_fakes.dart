import 'package:ai_os/core/result.dart';
import 'package:ai_os/tools/windows/control/window_controller.dart';

final class MockWindowController implements WindowController {
  MockWindowController({this.failureOperation});

  final WindowOperation? failureOperation;
  final List<WindowControlReceipt> calls = [];

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
    if (failureOperation == operation) {
      return Result.failure(
        Failure(
          'Mock ${operation.name} failure.',
          code: 'window_control_failed',
        ),
      );
    }
    final receipt = WindowControlReceipt(
      windowId: windowId,
      operation: operation,
    );
    calls.add(receipt);
    return Result.success(receipt);
  }
}
