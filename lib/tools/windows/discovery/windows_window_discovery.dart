import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../../core/result.dart';
import '../applications/application_registry.dart';
import 'window_discovery.dart';
import 'window_info.dart';

typedef _EnumWindowsProcNative = Int32 Function(IntPtr window, IntPtr data);
typedef _EnumWindowsNative =
    Int32 Function(
      Pointer<NativeFunction<_EnumWindowsProcNative>> callback,
      IntPtr data,
    );
typedef _EnumWindowsDart =
    int Function(
      Pointer<NativeFunction<_EnumWindowsProcNative>> callback,
      int data,
    );
typedef _WindowPredicateNative = Int32 Function(IntPtr window);
typedef _WindowPredicateDart = int Function(int window);
typedef _GetWindowTextLengthNative = Int32 Function(IntPtr window);
typedef _GetWindowTextLengthDart = int Function(int window);
typedef _GetWindowTextNative =
    Int32 Function(IntPtr window, Pointer<Utf16> text, Int32 maximumLength);
typedef _GetWindowTextDart =
    int Function(int window, Pointer<Utf16> text, int maximumLength);
typedef _GetWindowProcessIdNative =
    Uint32 Function(IntPtr window, Pointer<Uint32> processId);
typedef _GetWindowProcessIdDart =
    int Function(int window, Pointer<Uint32> processId);
typedef _GetForegroundWindowNative = IntPtr Function();
typedef _GetForegroundWindowDart = int Function();
typedef _OpenProcessNative =
    IntPtr Function(Uint32 access, Int32 inheritHandle, Uint32 processId);
typedef _OpenProcessDart =
    int Function(int access, int inheritHandle, int processId);
typedef _QueryProcessImageNameNative =
    Int32 Function(
      IntPtr process,
      Uint32 flags,
      Pointer<Utf16> executableName,
      Pointer<Uint32> size,
    );
typedef _QueryProcessImageNameDart =
    int Function(
      int process,
      int flags,
      Pointer<Utf16> executableName,
      Pointer<Uint32> size,
    );
typedef _CloseHandleNative = Int32 Function(IntPtr handle);
typedef _CloseHandleDart = int Function(int handle);

const int _processQueryLimitedInformation = 0x1000;
const int _maximumExecutablePathLength = 32768;

_WindowEnumeration? _activeEnumeration;

int _enumWindow(int window, int data) {
  try {
    _activeEnumeration?.add(window);
  } on Object {
    // A single unreadable window must not abort the desktop snapshot.
  }
  return 1;
}

final class _WindowEnumeration {
  _WindowEnumeration(this.discovery, this.activeWindow);

  final WindowsWindowDiscovery discovery;
  final int activeWindow;
  final List<WindowInfo> windows = [];

  void add(int window) {
    final info = discovery._readWindow(window, activeWindow: activeWindow);
    if (info != null && info.isVisible && info.title.isNotEmpty) {
      windows.add(info);
    }
  }
}

/// Read-only Win32 implementation backed by user32.dll and kernel32.dll.
final class WindowsWindowDiscovery implements WindowDiscovery {
  WindowsWindowDiscovery({required this.applicationRegistry});

  final ApplicationRegistry applicationRegistry;
  _WindowsApi? _apiInstance;

  _WindowsApi get _api => _apiInstance ??= _WindowsApi();

  @override
  Future<Result<List<WindowInfo>>> listWindows() async {
    if (!Platform.isWindows) {
      return const Result.failure(
        Failure(
          'Window discovery is currently supported only on Windows.',
          code: 'unsupported_platform',
        ),
      );
    }
    if (_activeEnumeration != null) {
      return const Result.failure(
        Failure(
          'Window discovery is already running.',
          code: 'discovery_in_progress',
        ),
      );
    }

    try {
      final enumeration = _WindowEnumeration(this, _api.getForegroundWindow());
      _activeEnumeration = enumeration;
      final callback = Pointer.fromFunction<_EnumWindowsProcNative>(
        _enumWindow,
        0,
      );
      final succeeded = _api.enumWindows(callback, 0) != 0;
      if (!succeeded) {
        return const Result.failure(
          Failure('Windows enumeration failed.', code: 'discovery_failed'),
        );
      }
      return Result.success(List.unmodifiable(enumeration.windows));
    } on Object catch (error) {
      return Result.failure(
        Failure('Windows enumeration failed: $error', code: 'discovery_failed'),
      );
    } finally {
      _activeEnumeration = null;
    }
  }

  @override
  Future<Result<WindowInfo?>> getActiveWindow() async {
    if (!Platform.isWindows) {
      return const Result.failure(
        Failure(
          'Window discovery is currently supported only on Windows.',
          code: 'unsupported_platform',
        ),
      );
    }
    try {
      final window = _api.getForegroundWindow();
      if (window == 0) {
        return const Result.success(null);
      }
      return Result.success(_readWindow(window, activeWindow: window));
    } on Object catch (error) {
      return Result.failure(
        Failure(
          'Active-window discovery failed: $error',
          code: 'discovery_failed',
        ),
      );
    }
  }

  WindowInfo? _readWindow(int window, {required int activeWindow}) {
    final visible = _api.isWindowVisible(window) != 0;
    final titleLength = _api.getWindowTextLength(window);
    if (titleLength <= 0) {
      return null;
    }

    final titleBuffer = calloc<Uint16>(titleLength + 1);
    final processIdPointer = calloc<Uint32>();
    try {
      final copied = _api.getWindowText(
        window,
        titleBuffer.cast<Utf16>(),
        titleLength + 1,
      );
      if (copied <= 0) {
        return null;
      }
      _api.getWindowProcessId(window, processIdPointer);
      final processId = processIdPointer.value;
      final processName = _getProcessName(processId);
      return WindowInfo(
        id: 'windows:window:${window.toRadixString(16)}',
        title: titleBuffer.cast<Utf16>().toDartString(length: copied).trim(),
        processId: processId,
        processName: processName,
        applicationId: _applicationIdFor(processName),
        isVisible: visible,
        isMinimized: _api.isIconic(window) != 0,
        isMaximized: _api.isZoomed(window) != 0,
        isActive: window == activeWindow,
      );
    } finally {
      calloc.free(titleBuffer);
      calloc.free(processIdPointer);
    }
  }

  String? _getProcessName(int processId) {
    if (processId == 0) {
      return null;
    }
    final process = _api.openProcess(
      _processQueryLimitedInformation,
      0,
      processId,
    );
    if (process == 0) {
      return null;
    }

    final pathBuffer = calloc<Uint16>(_maximumExecutablePathLength);
    final size = calloc<Uint32>()..value = _maximumExecutablePathLength;
    try {
      final succeeded = _api.queryFullProcessImageName(
        process,
        0,
        pathBuffer.cast<Utf16>(),
        size,
      );
      if (succeeded == 0 || size.value == 0) {
        return null;
      }
      final fullPath = pathBuffer.cast<Utf16>().toDartString(
        length: size.value,
      );
      return fullPath.split(RegExp(r'[\\/]')).last;
    } finally {
      calloc.free(pathBuffer);
      calloc.free(size);
      _api.closeHandle(process);
    }
  }

  String? _applicationIdFor(String? processName) {
    if (processName == null) {
      return null;
    }
    final normalizedName = processName.toLowerCase();
    for (final application in applicationRegistry.listKnownApplications()) {
      if (application.executableNames.any(
        (name) => name.toLowerCase() == normalizedName,
      )) {
        return application.id;
      }
    }
    return null;
  }
}

final class _WindowsApi {
  _WindowsApi()
    : enumWindows = DynamicLibrary.open(
        'user32.dll',
      ).lookupFunction<_EnumWindowsNative, _EnumWindowsDart>('EnumWindows'),
      isWindowVisible = DynamicLibrary.open('user32.dll')
          .lookupFunction<_WindowPredicateNative, _WindowPredicateDart>(
            'IsWindowVisible',
          ),
      isIconic = DynamicLibrary.open('user32.dll')
          .lookupFunction<_WindowPredicateNative, _WindowPredicateDart>(
            'IsIconic',
          ),
      isZoomed = DynamicLibrary.open('user32.dll')
          .lookupFunction<_WindowPredicateNative, _WindowPredicateDart>(
            'IsZoomed',
          ),
      getWindowTextLength = DynamicLibrary.open('user32.dll')
          .lookupFunction<_GetWindowTextLengthNative, _GetWindowTextLengthDart>(
            'GetWindowTextLengthW',
          ),
      getWindowText = DynamicLibrary.open('user32.dll')
          .lookupFunction<_GetWindowTextNative, _GetWindowTextDart>(
            'GetWindowTextW',
          ),
      getWindowProcessId = DynamicLibrary.open('user32.dll')
          .lookupFunction<_GetWindowProcessIdNative, _GetWindowProcessIdDart>(
            'GetWindowThreadProcessId',
          ),
      getForegroundWindow = DynamicLibrary.open('user32.dll')
          .lookupFunction<_GetForegroundWindowNative, _GetForegroundWindowDart>(
            'GetForegroundWindow',
          ),
      openProcess = DynamicLibrary.open(
        'kernel32.dll',
      ).lookupFunction<_OpenProcessNative, _OpenProcessDart>('OpenProcess'),
      queryFullProcessImageName = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<
            _QueryProcessImageNameNative,
            _QueryProcessImageNameDart
          >('QueryFullProcessImageNameW'),
      closeHandle = DynamicLibrary.open(
        'kernel32.dll',
      ).lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');

  final _EnumWindowsDart enumWindows;
  final _WindowPredicateDart isWindowVisible;
  final _WindowPredicateDart isIconic;
  final _WindowPredicateDart isZoomed;
  final _GetWindowTextLengthDart getWindowTextLength;
  final _GetWindowTextDart getWindowText;
  final _GetWindowProcessIdDart getWindowProcessId;
  final _GetForegroundWindowDart getForegroundWindow;
  final _OpenProcessDart openProcess;
  final _QueryProcessImageNameDart queryFullProcessImageName;
  final _CloseHandleDart closeHandle;
}
