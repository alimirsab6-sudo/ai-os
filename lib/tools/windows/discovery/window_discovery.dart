import '../../../core/result.dart';
import 'window_info.dart';

abstract interface class WindowDiscovery {
  Future<Result<List<WindowInfo>>> listWindows();
  Future<Result<WindowInfo?>> getActiveWindow();
}

