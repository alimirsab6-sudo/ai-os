import 'package:ai_os/core/result.dart';
import 'package:ai_os/tools/windows/ui_automation/ui_automation.dart';
import 'package:ai_os/tools/windows/ui_automation/ui_element.dart';

final class MockUiAutomation implements UiAutomation {
  MockUiAutomation({this.failure, this.invokeFailure, this.setValueFailure});

  final Failure? failure;
  final Failure? invokeFailure;
  final Failure? setValueFailure;
  int inspectCallCount = 0;
  int? lastMaxDepth;
  int? lastMaxElements;
  UiInspectionResult? _lastInspection;
  int invokeCallCount = 0;
  String? invokedWindowId;
  String? invokedElementId;
  int setValueCallCount = 0;
  String? valueWindowId;
  String? valueElementId;
  String? setValueText;

  static final tree = <UiElement>[
    UiElement(
      id: 'uia:abc:0',
      name: 'Test Window',
      controlType: UiControlType.window,
      isEnabled: true,
      isVisible: true,
      isFocused: true,
      depth: 0,
      supportedPatterns: const {},
    ),
    UiElement(
      id: 'uia:abc:1',
      parentId: 'uia:abc:0',
      name: 'Toolbar',
      controlType: UiControlType.unknown,
      isEnabled: true,
      isVisible: true,
      isFocused: false,
      depth: 1,
    ),
    UiElement(
      id: 'uia:abc:2',
      parentId: 'uia:abc:1',
      name: 'Save',
      automationId: 'saveButton',
      controlType: UiControlType.button,
      className: 'Button',
      isEnabled: true,
      isVisible: true,
      isFocused: false,
      depth: 2,
      supportedPatterns: const {UiPattern.invoke},
    ),
    UiElement(
      id: 'uia:abc:3',
      parentId: 'uia:abc:1',
      name: 'Name',
      controlType: UiControlType.edit,
      isEnabled: true,
      isVisible: true,
      isFocused: false,
      depth: 2,
      supportedPatterns: const {UiPattern.value},
      isValueReadOnly: false,
    ),
    UiElement(
      id: 'uia:abc:4',
      parentId: 'uia:abc:1',
      name: 'Read only',
      controlType: UiControlType.edit,
      isEnabled: true,
      isVisible: true,
      isFocused: false,
      depth: 2,
      supportedPatterns: const {UiPattern.value},
      isValueReadOnly: true,
    ),
  ];

  @override
  Future<Result<UiInspectionResult>> inspectWindow(
    String windowId, {
    required int maxDepth,
    required int maxElements,
  }) async {
    inspectCallCount++;
    lastMaxDepth = maxDepth;
    lastMaxElements = maxElements;
    if (failure case final failure?) {
      return Result.failure(failure);
    }
    final depthLimited = tree
        .where((element) => element.depth <= maxDepth)
        .toList(growable: false);
    final limited = depthLimited.take(maxElements).toList(growable: false);
    final inspection = UiInspectionResult(
      windowId: windowId,
      elements: limited,
      maxDepth: maxDepth,
      maxElements: maxElements,
      wasTruncated: limited.length < tree.length,
    );
    _lastInspection = inspection;
    return Result.success(inspection);
  }

  @override
  Future<Result<UiElement>> getRootElement(String windowId) async =>
      Result.success(tree.first);

  @override
  Future<Result<List<UiElement>>> getChildren(String elementId) async =>
      Result.success(
        tree.where((element) => element.parentId == elementId).toList(),
      );

  @override
  Future<Result<List<UiElement>>> findElements(UiElementQuery query) async =>
      Result.success(tree.where(query.matches).toList());

  @override
  Future<Result<UiElement>> getElement(String elementId) async {
    for (final element in _lastInspection?.elements ?? tree) {
      if (element.id == elementId) {
        return Result.success(element);
      }
    }
    return const Result.failure(
      Failure('Element is stale.', code: 'stale_ui_element'),
    );
  }

  @override
  Future<Result<UiInvokeReceipt>> invoke(
    String windowId,
    String elementId,
  ) async {
    invokeCallCount++;
    invokedWindowId = windowId;
    invokedElementId = elementId;
    if (invokeFailure case final failure?) {
      return Result.failure(failure);
    }
    final elementResult = await getElement(elementId);
    if (elementResult case Failed<UiElement>(:final failure)) {
      return Result.failure(failure);
    }
    final element = (elementResult as Success<UiElement>).value;
    if (!element.supportedPatterns.contains(UiPattern.invoke)) {
      return const Result.failure(
        Failure('Invoke is not supported.', code: 'invoke_not_supported'),
      );
    }
    return Result.success(
      UiInvokeReceipt(windowId: windowId, elementId: elementId),
    );
  }

  @override
  Future<Result<UiSetValueReceipt>> setValue(
    String windowId,
    String elementId,
    String value,
  ) async {
    setValueCallCount++;
    valueWindowId = windowId;
    valueElementId = elementId;
    setValueText = value;
    if (setValueFailure case final failure?) {
      return Result.failure(failure);
    }
    final elementResult = await getElement(elementId);
    if (elementResult case Failed<UiElement>(:final failure)) {
      return Result.failure(failure);
    }
    final element = (elementResult as Success<UiElement>).value;
    if (!element.supportedPatterns.contains(UiPattern.value)) {
      return const Result.failure(
        Failure('Value is not supported.', code: 'value_not_supported'),
      );
    }
    if (element.isValueReadOnly == true) {
      return const Result.failure(
        Failure('Element is read-only.', code: 'value_read_only'),
      );
    }
    return Result.success(
      UiSetValueReceipt(windowId: windowId, elementId: elementId),
    );
  }
}
