import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../../core/result.dart';
import '../discovery/window_discovery.dart';
import 'ui_automation.dart';
import 'ui_element.dart';
import 'windows_ui_automation_mappings.dart';

/// UI Automation client backed by COM, with all native work off the UI isolate.
final class WindowsUiAutomation implements UiAutomation {
  WindowsUiAutomation({required this.windowDiscovery});

  final WindowDiscovery windowDiscovery;
  UiInspectionResult? _lastInspection;
  final Map<String, _ElementLocator> _elementLocators = {};
  int _inspectionSequence = 0;

  @override
  Future<Result<UiInspectionResult>> inspectWindow(
    String windowId, {
    required int maxDepth,
    required int maxElements,
  }) async {
    final limitsFailure = _validateLimits(maxDepth, maxElements);
    if (limitsFailure != null) {
      return Result.failure(limitsFailure);
    }
    if (!Platform.isWindows) {
      return const Result.failure(
        Failure(
          'UI inspection is currently supported only on Windows.',
          code: 'unsupported_platform',
        ),
      );
    }

    final handleResult = await _resolveCurrentHandle(windowId);
    if (handleResult case Failed<int>(:final failure)) {
      return Result.failure(failure);
    }

    try {
      final sessionId =
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
          '${(_inspectionSequence++).toRadixString(16).padLeft(4, '0')}';
      final nativeResult = await Isolate.run(
        () => _inspectNativeWindow(
          (handleResult as Success<int>).value,
          maxDepth,
          maxElements,
          sessionId,
        ),
      );
      if (nativeResult['failure'] case final String message) {
        return Result.failure(
          Failure(message, code: nativeResult['failure_code'] as String?),
        );
      }
      final nativeElements = (nativeResult['elements']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      final elements = <UiElement>[];
      final locators = <String, _ElementLocator>{};
      for (final nativeElement in nativeElements) {
        final element = UiElement.fromMap(nativeElement);
        elements.add(element);
        locators[element.id] = _ElementLocator(
          windowId: windowId,
          path: (nativeElement['_path']! as List<Object?>).cast<int>(),
          runtimeId: (nativeElement['_runtime_id']! as List<Object?>)
              .cast<int>(),
          name: element.name,
          automationId: element.automationId,
          className: element.className,
          controlType: element.controlType,
        );
      }
      final result = UiInspectionResult(
        windowId: windowId,
        elements: elements,
        maxDepth: maxDepth,
        maxElements: maxElements,
        wasTruncated: nativeResult['was_truncated']! as bool,
      );
      _lastInspection = result;
      _elementLocators
        ..clear()
        ..addAll(locators);
      return Result.success(result);
    } on Object catch (error) {
      return Result.failure(
        Failure(
          'Windows UI inspection failed: $error',
          code: 'ui_inspection_failed',
        ),
      );
    }
  }

  @override
  Future<Result<UiElement>> getRootElement(String windowId) async {
    final result = await inspectWindow(windowId, maxDepth: 0, maxElements: 1);
    return result.fold((inspection) {
      final root = inspection.rootElement;
      return root == null
          ? const Result.failure(
              Failure(
                'No root UI element was found.',
                code: 'element_not_found',
              ),
            )
          : Result.success(root);
    }, Result.failure);
  }

  @override
  Future<Result<List<UiElement>>> getChildren(String elementId) async {
    final inspection = _lastInspection;
    if (inspection == null) {
      return const Result.failure(
        Failure(
          'Inspect a window before querying elements.',
          code: 'inspection_required',
        ),
      );
    }
    return Result.success(
      inspection.elements
          .where((element) => element.parentId == elementId)
          .toList(growable: false),
    );
  }

  @override
  Future<Result<List<UiElement>>> findElements(UiElementQuery query) async {
    final inspection = _lastInspection;
    if (inspection == null) {
      return const Result.failure(
        Failure(
          'Inspect a window before querying elements.',
          code: 'inspection_required',
        ),
      );
    }
    return Result.success(
      inspection.elements.where(query.matches).toList(growable: false),
    );
  }

  @override
  Future<Result<UiElement>> getElement(String elementId) async {
    final inspection = _lastInspection;
    if (inspection == null) {
      return const Result.failure(
        Failure(
          'Inspect a window before querying elements.',
          code: 'inspection_required',
        ),
      );
    }
    for (final element in inspection.elements) {
      if (element.id == elementId) {
        return Result.success(element);
      }
    }
    return const Result.failure(
      Failure(
        'UI element is stale or was not found.',
        code: 'stale_ui_element',
      ),
    );
  }

  @override
  Future<Result<UiInvokeReceipt>> invoke(
    String windowId,
    String elementId,
  ) async {
    if (!Platform.isWindows) {
      return const Result.failure(
        Failure(
          'UI invocation is currently supported only on Windows.',
          code: 'unsupported_platform',
        ),
      );
    }
    final locator = _elementLocators[elementId];
    if (locator == null || locator.windowId != windowId) {
      return const Result.failure(
        Failure(
          'The UI element is stale or does not belong to the target window.',
          code: 'stale_ui_element',
        ),
      );
    }
    final handleResult = await _resolveCurrentHandle(windowId);
    if (handleResult case Failed<int>(:final failure)) {
      return Result.failure(failure);
    }
    try {
      final locatorData = locator.toMap();
      final nativeResult = await Isolate.run(
        () => _invokeNativeElement(
          (handleResult as Success<int>).value,
          locatorData,
        ),
      );
      if (nativeResult['failure'] case final String message) {
        return Result.failure(
          Failure(message, code: nativeResult['failure_code'] as String?),
        );
      }
      _elementLocators.remove(elementId);
      return Result.success(
        UiInvokeReceipt(windowId: windowId, elementId: elementId),
      );
    } on Object catch (error) {
      return Result.failure(
        Failure(
          'Windows UI invocation failed: $error',
          code: 'ui_invoke_failed',
        ),
      );
    }
  }

  Failure? _validateLimits(int maxDepth, int maxElements) {
    if (maxDepth < 0 || maxDepth > UiTraversalLimits.maximumDepth) {
      return const Failure(
        'maxDepth is outside the supported range.',
        code: 'invalid_traversal_limit',
      );
    }
    if (maxElements < 1 || maxElements > UiTraversalLimits.maximumElements) {
      return const Failure(
        'maxElements is outside the supported range.',
        code: 'invalid_traversal_limit',
      );
    }
    return null;
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
    final discoveryResult = await windowDiscovery.listWindows();
    if (discoveryResult case Failed(:final failure)) {
      return Result.failure(failure);
    }
    final windows = (discoveryResult as Success).value;
    if (!windows.any((window) => window.id == windowId)) {
      return Result.failure(
        Failure(
          'Window "$windowId" is no longer discoverable.',
          code: 'window_not_found',
        ),
      );
    }
    return Result.success(int.parse(match.group(1)!, radix: 16));
  }
}

Map<String, Object?> _inspectNativeWindow(
  int windowHandle,
  int maxDepth,
  int maxElements,
  String session,
) {
  final api = _ComApi();
  final initializeResult = api.coInitializeEx(nullptr, 0);
  final shouldUninitialize = initializeResult >= 0;
  if (initializeResult < 0 && initializeResult != _rpcChangedMode) {
    return _nativeFailure('COM initialization failed.', initializeResult);
  }

  Pointer<Void> automation = nullptr;
  Pointer<Void> walker = nullptr;
  final pending = ListQueue<_PendingElement>();
  try {
    final automationResult = api.createAutomation();
    if (automationResult case Failed<Pointer<Void>>(:final failure)) {
      return {'failure': failure.message, 'failure_code': failure.code};
    }
    automation = (automationResult as Success<Pointer<Void>>).value;

    final rootResult = _elementFromHandle(automation, windowHandle);
    if (rootResult == nullptr) {
      return _nativeFailureMessage(
        'UI Automation could not resolve the target window.',
        'ui_root_not_found',
      );
    }
    final walkerResult = _controlViewWalker(automation);
    if (walkerResult == nullptr) {
      _release(rootResult);
      return _nativeFailureMessage(
        'UI Automation control-view walker is unavailable.',
        'ui_inspection_failed',
      );
    }
    walker = walkerResult;
    pending.add(
      _PendingElement(rootResult, parentId: null, depth: 0, path: const []),
    );

    final elements = <Map<String, Object?>>[];
    var wasTruncated = false;
    var ordinal = 0;

    while (pending.isNotEmpty && elements.length < maxElements) {
      final current = pending.removeFirst();
      final elementId = 'uia:$session:${ordinal++}';
      try {
        elements.add(
          _readElement(
            current.pointer,
            elementId,
            current.parentId,
            current.depth,
            current.path,
          ),
        );

        if (current.depth >= maxDepth) {
          final child = _firstChild(walker, current.pointer);
          if (child != nullptr) {
            wasTruncated = true;
            _release(child);
          }
          continue;
        }

        var child = _firstChild(walker, current.pointer);
        var childIndex = 0;
        while (child != nullptr) {
          if (elements.length + pending.length >= maxElements) {
            wasTruncated = true;
            _release(child);
            break;
          }
          final next = _nextSibling(walker, child);
          pending.add(
            _PendingElement(
              child,
              parentId: elementId,
              depth: current.depth + 1,
              path: [...current.path, childIndex],
            ),
          );
          child = next;
          childIndex++;
        }
      } finally {
        _release(current.pointer);
      }
    }

    if (pending.isNotEmpty) {
      wasTruncated = true;
    }
    return {'elements': elements, 'was_truncated': wasTruncated};
  } on Object catch (error) {
    return _nativeFailureMessage(
      'Native UI Automation traversal failed: $error',
      'ui_inspection_failed',
    );
  } finally {
    while (pending.isNotEmpty) {
      _release(pending.removeFirst().pointer);
    }
    if (walker != nullptr) {
      _release(walker);
    }
    if (automation != nullptr) {
      _release(automation);
    }
    if (shouldUninitialize) {
      api.coUninitialize();
    }
  }
}

Map<String, Object?> _readElement(
  Pointer<Void> element,
  String id,
  String? parentId,
  int depth,
  List<int> path,
) {
  final controlType = WindowsUiAutomationMappings.controlTypeFromId(
    _getIntProperty(element, 21),
  );
  return {
    'id': id,
    'parent_id': parentId,
    'name': _getStringProperty(element, 23),
    'automation_id': _emptyToNull(_getStringProperty(element, 29)),
    'control_type': controlType.name,
    'class_name': _emptyToNull(_getStringProperty(element, 30)),
    'is_enabled': _getBoolProperty(element, 28),
    'is_visible': !_getBoolProperty(element, 38),
    'is_focused': _getBoolProperty(element, 26),
    'depth': depth,
    'supported_patterns': _getSupportedPatterns(element),
    '_path': path,
    '_runtime_id': _getRuntimeId(element),
  };
}

List<int> _getRuntimeId(Pointer<Void> element) {
  final output = calloc<Pointer<Void>>();
  try {
    final method = _method(element, 4)
        .cast<NativeFunction<_GetRuntimeIdNative>>()
        .asFunction<_GetRuntimeIdDart>();
    if (method(element, output) < 0 || output.value == nullptr) {
      return const [];
    }
    final safeArray = output.value;
    try {
      final lower = calloc<Int32>();
      final upper = calloc<Int32>();
      try {
        if (_ComApi.safeArrayGetLBound(safeArray, 1, lower) < 0 ||
            _ComApi.safeArrayGetUBound(safeArray, 1, upper) < 0) {
          return const [];
        }
        final result = <int>[];
        final index = calloc<Int32>();
        final value = calloc<Int32>();
        try {
          for (var current = lower.value; current <= upper.value; current++) {
            index.value = current;
            if (_ComApi.safeArrayGetElement(safeArray, index, value) < 0) {
              return const [];
            }
            result.add(value.value);
          }
        } finally {
          calloc.free(index);
          calloc.free(value);
        }
        return result;
      } finally {
        calloc.free(lower);
        calloc.free(upper);
      }
    } finally {
      _ComApi.safeArrayDestroy(safeArray);
    }
  } on Object {
    return const [];
  } finally {
    calloc.free(output);
  }
}

Map<String, Object?> _invokeNativeElement(
  int windowHandle,
  Map<String, Object?> locator,
) {
  final api = _ComApi();
  final initializeResult = api.coInitializeEx(nullptr, 0);
  final shouldUninitialize = initializeResult >= 0;
  if (initializeResult < 0 && initializeResult != _rpcChangedMode) {
    return _nativeFailure('COM initialization failed.', initializeResult);
  }

  Pointer<Void> automation = nullptr;
  Pointer<Void> walker = nullptr;
  Pointer<Void> element = nullptr;
  Pointer<Void> invokePattern = nullptr;
  try {
    final automationResult = api.createAutomation();
    if (automationResult case Failed<Pointer<Void>>(:final failure)) {
      return {'failure': failure.message, 'failure_code': failure.code};
    }
    automation = (automationResult as Success<Pointer<Void>>).value;
    element = _elementFromHandle(automation, windowHandle);
    if (element == nullptr) {
      return _nativeFailureMessage(
        'The target window no longer exposes a UI Automation root.',
        'stale_ui_element',
      );
    }
    walker = _controlViewWalker(automation);
    if (walker == nullptr) {
      return _nativeFailureMessage(
        'UI Automation control-view walker is unavailable.',
        'ui_invoke_failed',
      );
    }

    for (final childIndex in (locator['path']! as List<Object?>).cast<int>()) {
      var nextElement = _firstChild(walker, element);
      if (nextElement == nullptr) {
        return _nativeFailureMessage(
          'The UI element no longer exists at its inspected location.',
          'stale_ui_element',
        );
      }
      for (var index = 0; index < childIndex; index++) {
        final sibling = _nextSibling(walker, nextElement);
        _release(nextElement);
        nextElement = sibling;
        if (nextElement == nullptr) {
          return _nativeFailureMessage(
            'The UI element no longer exists at its inspected location.',
            'stale_ui_element',
          );
        }
      }
      _release(element);
      element = nextElement;
    }

    final expectedRuntimeId = (locator['runtime_id']! as List<Object?>)
        .cast<int>();
    final currentRuntimeId = _getRuntimeId(element);
    if (expectedRuntimeId.isEmpty ||
        currentRuntimeId.isEmpty ||
        !_sameInts(expectedRuntimeId, currentRuntimeId) ||
        !_matchesFingerprint(element, locator)) {
      return _nativeFailureMessage(
        'The UI element changed or is stale.',
        'stale_ui_element',
      );
    }

    final patternOutput = calloc<Pointer<Void>>();
    try {
      final getPattern = _method(
        element,
        16,
      ).cast<NativeFunction<_GetPatternNative>>().asFunction<_GetPatternDart>();
      final patternResult = getPattern(element, 10000, patternOutput);
      if (patternResult < 0 || patternOutput.value == nullptr) {
        return _nativeFailureMessage(
          'The UI element does not support the Invoke pattern.',
          'invoke_not_supported',
        );
      }
      invokePattern = patternOutput.value;
    } finally {
      calloc.free(patternOutput);
    }

    final invoke = _method(
      invokePattern,
      3,
    ).cast<NativeFunction<_InvokeNative>>().asFunction<_InvokeDart>();
    final invokeResult = invoke(invokePattern);
    if (invokeResult < 0) {
      return _nativeFailure(
        'The UI Automation Invoke operation failed.',
        invokeResult,
      );
    }
    return {'success': true};
  } on Object catch (error) {
    return _nativeFailureMessage(
      'Native UI invocation failed: $error',
      'ui_invoke_failed',
    );
  } finally {
    if (invokePattern != nullptr) _release(invokePattern);
    if (element != nullptr) _release(element);
    if (walker != nullptr) _release(walker);
    if (automation != nullptr) _release(automation);
    if (shouldUninitialize) api.coUninitialize();
  }
}

bool _matchesFingerprint(Pointer<Void> element, Map<String, Object?> locator) {
  final controlType = WindowsUiAutomationMappings.controlTypeFromId(
    _getIntProperty(element, 21),
  );
  return _getStringProperty(element, 23) == locator['name'] &&
      _emptyToNull(_getStringProperty(element, 29)) ==
          locator['automation_id'] &&
      _emptyToNull(_getStringProperty(element, 30)) == locator['class_name'] &&
      controlType.name == locator['control_type'];
}

bool _sameInts(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

List<String> _getSupportedPatterns(Pointer<Void> element) {
  final patterns = <String>[];
  for (final patternId in WindowsUiAutomationMappings.patternIds) {
    final output = calloc<Pointer<Void>>();
    try {
      final method = _method(
        element,
        16,
      ).cast<NativeFunction<_GetPatternNative>>().asFunction<_GetPatternDart>();
      final result = method(element, patternId, output);
      if (result >= 0 && output.value != nullptr) {
        final pattern = WindowsUiAutomationMappings.patternFromId(patternId);
        if (pattern != null) {
          patterns.add(pattern.name);
        }
        _release(output.value);
      }
    } finally {
      calloc.free(output);
    }
  }
  return patterns;
}

String _getStringProperty(Pointer<Void> element, int methodIndex) {
  final output = calloc<Pointer<Utf16>>();
  try {
    final getter = _method(
      element,
      methodIndex,
    ).cast<NativeFunction<_GetStringNative>>().asFunction<_GetStringDart>();
    if (getter(element, output) < 0 || output.value == nullptr) {
      return '';
    }
    try {
      final length = _ComApi.sysStringLength(output.value);
      return output.value.toDartString(length: length);
    } finally {
      _ComApi.freeString(output.value);
    }
  } on Object {
    return '';
  } finally {
    calloc.free(output);
  }
}

int _getIntProperty(Pointer<Void> element, int methodIndex) {
  final output = calloc<Int32>();
  try {
    final getter = _method(
      element,
      methodIndex,
    ).cast<NativeFunction<_GetIntNative>>().asFunction<_GetIntDart>();
    return getter(element, output) >= 0 ? output.value : 0;
  } on Object {
    return 0;
  } finally {
    calloc.free(output);
  }
}

bool _getBoolProperty(Pointer<Void> element, int methodIndex) =>
    _getIntProperty(element, methodIndex) != 0;

Pointer<Void> _elementFromHandle(Pointer<Void> automation, int handle) {
  final output = calloc<Pointer<Void>>();
  try {
    final method = _method(automation, 6)
        .cast<NativeFunction<_ElementFromHandleNative>>()
        .asFunction<_ElementFromHandleDart>();
    return method(automation, handle, output) >= 0 ? output.value : nullptr;
  } finally {
    calloc.free(output);
  }
}

Pointer<Void> _controlViewWalker(Pointer<Void> automation) {
  final output = calloc<Pointer<Void>>();
  try {
    final method = _method(automation, 14)
        .cast<NativeFunction<_GetInterfaceNative>>()
        .asFunction<_GetInterfaceDart>();
    return method(automation, output) >= 0 ? output.value : nullptr;
  } finally {
    calloc.free(output);
  }
}

Pointer<Void> _firstChild(Pointer<Void> walker, Pointer<Void> element) =>
    _walk(walker, element, 4);

Pointer<Void> _nextSibling(Pointer<Void> walker, Pointer<Void> element) =>
    _walk(walker, element, 6);

Pointer<Void> _walk(
  Pointer<Void> walker,
  Pointer<Void> element,
  int methodIndex,
) {
  final output = calloc<Pointer<Void>>();
  try {
    final method = _method(
      walker,
      methodIndex,
    ).cast<NativeFunction<_WalkNative>>().asFunction<_WalkDart>();
    return method(walker, element, output) >= 0 ? output.value : nullptr;
  } finally {
    calloc.free(output);
  }
}

void _release(Pointer<Void> object) {
  if (object == nullptr) {
    return;
  }
  final release = _method(
    object,
    2,
  ).cast<NativeFunction<_ReleaseNative>>().asFunction<_ReleaseDart>();
  release(object);
}

Pointer<Void> _method(Pointer<Void> object, int index) {
  final vtable = object.cast<Pointer<Void>>().value;
  return (vtable.cast<Pointer<Void>>() + index).value;
}

String? _emptyToNull(String value) => value.isEmpty ? null : value;

Map<String, Object?> _nativeFailure(String message, int hresult) =>
    _nativeFailureMessage(
      '$message HRESULT 0x${hresult.toUnsigned(32).toRadixString(16)}.',
      'ui_inspection_failed',
    );

Map<String, Object?> _nativeFailureMessage(String message, String code) => {
  'failure': message,
  'failure_code': code,
};

final class _PendingElement {
  const _PendingElement(
    this.pointer, {
    required this.parentId,
    required this.depth,
    required this.path,
  });

  final Pointer<Void> pointer;
  final String? parentId;
  final int depth;
  final List<int> path;
}

final class _ElementLocator {
  const _ElementLocator({
    required this.windowId,
    required this.path,
    required this.runtimeId,
    required this.name,
    required this.automationId,
    required this.className,
    required this.controlType,
  });

  final String windowId;
  final List<int> path;
  final List<int> runtimeId;
  final String name;
  final String? automationId;
  final String? className;
  final UiControlType controlType;

  Map<String, Object?> toMap() => {
    'path': path,
    'runtime_id': runtimeId,
    'name': name,
    'automation_id': automationId,
    'class_name': className,
    'control_type': controlType.name,
  };
}

final class _Guid extends Struct {
  @Uint32()
  external int data1;

  @Uint16()
  external int data2;

  @Uint16()
  external int data3;

  @Array(8)
  external Array<Uint8> data4;
}

final class _ComApi {
  _ComApi() {
    final ole32 = DynamicLibrary.open('ole32.dll');
    coInitializeEx = ole32
        .lookupFunction<_CoInitializeExNative, _CoInitializeExDart>(
          'CoInitializeEx',
        );
    coUninitialize = ole32
        .lookupFunction<_CoUninitializeNative, _CoUninitializeDart>(
          'CoUninitialize',
        );
    coCreateInstance = ole32
        .lookupFunction<_CoCreateInstanceNative, _CoCreateInstanceDart>(
          'CoCreateInstance',
        );
  }

  late final _CoInitializeExDart coInitializeEx;
  late final _CoUninitializeDart coUninitialize;
  late final _CoCreateInstanceDart coCreateInstance;

  static final _SysFreeStringDart freeString = DynamicLibrary.open(
    'oleaut32.dll',
  ).lookupFunction<_SysFreeStringNative, _SysFreeStringDart>('SysFreeString');

  static final _SysStringLengthDart sysStringLength =
      DynamicLibrary.open(
        'oleaut32.dll',
      ).lookupFunction<_SysStringLengthNative, _SysStringLengthDart>(
        'SysStringLen',
      );

  static final _SafeArrayGetBoundDart safeArrayGetLBound =
      DynamicLibrary.open(
        'oleaut32.dll',
      ).lookupFunction<_SafeArrayGetBoundNative, _SafeArrayGetBoundDart>(
        'SafeArrayGetLBound',
      );

  static final _SafeArrayGetBoundDart safeArrayGetUBound =
      DynamicLibrary.open(
        'oleaut32.dll',
      ).lookupFunction<_SafeArrayGetBoundNative, _SafeArrayGetBoundDart>(
        'SafeArrayGetUBound',
      );

  static final _SafeArrayGetElementDart safeArrayGetElement =
      DynamicLibrary.open(
        'oleaut32.dll',
      ).lookupFunction<_SafeArrayGetElementNative, _SafeArrayGetElementDart>(
        'SafeArrayGetElement',
      );

  static final _SafeArrayDestroyDart safeArrayDestroy =
      DynamicLibrary.open(
        'oleaut32.dll',
      ).lookupFunction<_SafeArrayDestroyNative, _SafeArrayDestroyDart>(
        'SafeArrayDestroy',
      );

  Result<Pointer<Void>> createAutomation() {
    final classId = calloc<_Guid>();
    final interfaceId = calloc<_Guid>();
    final output = calloc<Pointer<Void>>();
    try {
      _writeGuid(classId, 0xff48dba4, 0x60ef, 0x4201, [
        0xaa,
        0x87,
        0x54,
        0x10,
        0x3e,
        0xef,
        0x59,
        0x4e,
      ]);
      _writeGuid(interfaceId, 0x30cbe57d, 0xd9d0, 0x452a, [
        0xab,
        0x13,
        0x7a,
        0xc5,
        0xac,
        0x48,
        0x25,
        0xee,
      ]);
      final result = coCreateInstance(classId, nullptr, 1, interfaceId, output);
      if (result < 0 || output.value == nullptr) {
        return Result.failure(
          Failure(
            'Could not create Microsoft UI Automation. HRESULT '
            '0x${result.toUnsigned(32).toRadixString(16)}.',
            code: 'ui_automation_unavailable',
          ),
        );
      }
      return Result.success(output.value);
    } finally {
      calloc.free(classId);
      calloc.free(interfaceId);
      calloc.free(output);
    }
  }
}

void _writeGuid(
  Pointer<_Guid> pointer,
  int data1,
  int data2,
  int data3,
  List<int> data4,
) {
  pointer.ref
    ..data1 = data1
    ..data2 = data2
    ..data3 = data3;
  for (var index = 0; index < data4.length; index++) {
    pointer.ref.data4[index] = data4[index];
  }
}

const int _rpcChangedMode = -2147417850;

typedef _CoInitializeExNative =
    Int32 Function(Pointer<Void> reserved, Uint32 apartmentType);
typedef _CoInitializeExDart =
    int Function(Pointer<Void> reserved, int apartmentType);
typedef _CoUninitializeNative = Void Function();
typedef _CoUninitializeDart = void Function();
typedef _CoCreateInstanceNative =
    Int32 Function(
      Pointer<_Guid> classId,
      Pointer<Void> outer,
      Uint32 context,
      Pointer<_Guid> interfaceId,
      Pointer<Pointer<Void>> output,
    );
typedef _CoCreateInstanceDart =
    int Function(
      Pointer<_Guid> classId,
      Pointer<Void> outer,
      int context,
      Pointer<_Guid> interfaceId,
      Pointer<Pointer<Void>> output,
    );
typedef _ElementFromHandleNative =
    Int32 Function(
      Pointer<Void> automation,
      IntPtr window,
      Pointer<Pointer<Void>> output,
    );
typedef _ElementFromHandleDart =
    int Function(
      Pointer<Void> automation,
      int window,
      Pointer<Pointer<Void>> output,
    );
typedef _GetInterfaceNative =
    Int32 Function(Pointer<Void> object, Pointer<Pointer<Void>> output);
typedef _GetInterfaceDart =
    int Function(Pointer<Void> object, Pointer<Pointer<Void>> output);
typedef _WalkNative =
    Int32 Function(
      Pointer<Void> walker,
      Pointer<Void> element,
      Pointer<Pointer<Void>> output,
    );
typedef _WalkDart =
    int Function(
      Pointer<Void> walker,
      Pointer<Void> element,
      Pointer<Pointer<Void>> output,
    );
typedef _GetStringNative =
    Int32 Function(Pointer<Void> element, Pointer<Pointer<Utf16>> output);
typedef _GetStringDart =
    int Function(Pointer<Void> element, Pointer<Pointer<Utf16>> output);
typedef _GetIntNative =
    Int32 Function(Pointer<Void> element, Pointer<Int32> output);
typedef _GetIntDart =
    int Function(Pointer<Void> element, Pointer<Int32> output);
typedef _GetPatternNative =
    Int32 Function(
      Pointer<Void> element,
      Int32 patternId,
      Pointer<Pointer<Void>> output,
    );
typedef _GetPatternDart =
    int Function(
      Pointer<Void> element,
      int patternId,
      Pointer<Pointer<Void>> output,
    );
typedef _GetRuntimeIdNative =
    Int32 Function(Pointer<Void> element, Pointer<Pointer<Void>> output);
typedef _GetRuntimeIdDart =
    int Function(Pointer<Void> element, Pointer<Pointer<Void>> output);
typedef _InvokeNative = Int32 Function(Pointer<Void> pattern);
typedef _InvokeDart = int Function(Pointer<Void> pattern);
typedef _ReleaseNative = Uint32 Function(Pointer<Void> object);
typedef _ReleaseDart = int Function(Pointer<Void> object);
typedef _SysFreeStringNative = Void Function(Pointer<Utf16> string);
typedef _SysFreeStringDart = void Function(Pointer<Utf16> string);
typedef _SysStringLengthNative = Uint32 Function(Pointer<Utf16> string);
typedef _SysStringLengthDart = int Function(Pointer<Utf16> string);
typedef _SafeArrayGetBoundNative =
    Int32 Function(Pointer<Void> array, Uint32 dimension, Pointer<Int32> bound);
typedef _SafeArrayGetBoundDart =
    int Function(Pointer<Void> array, int dimension, Pointer<Int32> bound);
typedef _SafeArrayGetElementNative =
    Int32 Function(
      Pointer<Void> array,
      Pointer<Int32> index,
      Pointer<Int32> value,
    );
typedef _SafeArrayGetElementDart =
    int Function(
      Pointer<Void> array,
      Pointer<Int32> index,
      Pointer<Int32> value,
    );
typedef _SafeArrayDestroyNative = Int32 Function(Pointer<Void> array);
typedef _SafeArrayDestroyDart = int Function(Pointer<Void> array);
