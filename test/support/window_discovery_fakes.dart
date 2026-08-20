import 'package:ai_os/core/result.dart';
import 'package:ai_os/tools/windows/discovery/window_discovery.dart';
import 'package:ai_os/tools/windows/discovery/window_info.dart';

const chromeWindow = WindowInfo(
  id: 'windows:window:123',
  title: 'Chrome - Example',
  processId: 42,
  processName: 'chrome.exe',
  applicationId: 'chrome',
  isVisible: true,
  isMinimized: false,
  isMaximized: true,
  isActive: true,
);

final class MockWindowDiscovery implements WindowDiscovery {
  MockWindowDiscovery({
    Result<List<WindowInfo>>? listResult,
    Result<WindowInfo?>? activeResult,
  }) : listResult = listResult ?? const Result.success([chromeWindow]),
       activeResult = activeResult ?? const Result.success(chromeWindow);

  Result<List<WindowInfo>> listResult;
  Result<WindowInfo?> activeResult;
  int listCallCount = 0;
  int activeCallCount = 0;

  @override
  Future<Result<List<WindowInfo>>> listWindows() async {
    listCallCount++;
    return listResult;
  }

  @override
  Future<Result<WindowInfo?>> getActiveWindow() async {
    activeCallCount++;
    return activeResult;
  }
}

