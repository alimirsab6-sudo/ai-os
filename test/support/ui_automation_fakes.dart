import 'package:ai_os/core/result.dart';
import 'package:ai_os/tools/windows/ui_automation/ui_automation.dart';
import 'package:ai_os/tools/windows/ui_automation/ui_element.dart';

final class MockUiAutomation implements UiAutomation {
  MockUiAutomation({this.failure});

  final Failure? failure;
  int inspectCallCount = 0;
  int? lastMaxDepth;
  int? lastMaxElements;
  UiInspectionResult? _lastInspection;

  static final tree = <UiElement>[
    UiElement(
      id: 'uia:test:0',
      name: 'Test Window',
      controlType: UiControlType.window,
      isEnabled: true,
      isVisible: true,
      isFocused: true,
      depth: 0,
      supportedPatterns: const {},
    ),
    UiElement(
      id: 'uia:test:1',
      parentId: 'uia:test:0',
      name: 'Toolbar',
      controlType: UiControlType.unknown,
      isEnabled: true,
      isVisible: true,
      isFocused: false,
      depth: 1,
    ),
    UiElement(
      id: 'uia:test:2',
      parentId: 'uia:test:1',
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
      id: 'uia:test:3',
      parentId: 'uia:test:1',
      name: 'Name',
      controlType: UiControlType.edit,
      isEnabled: true,
      isVisible: true,
      isFocused: false,
      depth: 2,
      supportedPatterns: const {UiPattern.value},
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
      Failure('Element missing.', code: 'element_not_found'),
    );
  }
}
