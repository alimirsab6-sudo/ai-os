import '../../../core/result.dart';
import 'ui_element.dart';

final class UiTraversalLimits {
  const UiTraversalLimits._();

  static const defaultMaxDepth = 3;
  static const defaultMaxElements = 100;
  static const maximumDepth = 10;
  static const maximumElements = 500;
}

final class UiValueLimits {
  const UiValueLimits._();

  /// Bounds isolate messages and native BSTR allocations without restricting
  /// ordinary text-entry scenarios.
  static const maximumCodeUnits = 1024 * 1024;
}

final class UiElementQuery {
  const UiElementQuery({this.name, this.automationId, this.controlType});

  final String? name;
  final String? automationId;
  final UiControlType? controlType;

  bool matches(UiElement element) =>
      (name == null || element.name == name) &&
      (automationId == null || element.automationId == automationId) &&
      (controlType == null || element.controlType == controlType);
}

abstract interface class UiAutomation {
  Future<Result<UiInspectionResult>> inspectWindow(
    String windowId, {
    required int maxDepth,
    required int maxElements,
  });

  Future<Result<UiElement>> getRootElement(String windowId);
  Future<Result<List<UiElement>>> getChildren(String elementId);
  Future<Result<List<UiElement>>> findElements(UiElementQuery query);
  Future<Result<UiElement>> getElement(String elementId);
  Future<Result<UiInvokeReceipt>> invoke(String windowId, String elementId);
  Future<Result<UiSetValueReceipt>> setValue(
    String windowId,
    String elementId,
    String value,
  );
}

final class UiInvokeReceipt {
  const UiInvokeReceipt({required this.windowId, required this.elementId});

  final String windowId;
  final String elementId;
}

final class UiSetValueReceipt {
  const UiSetValueReceipt({required this.windowId, required this.elementId});

  final String windowId;
  final String elementId;
}

