enum UiControlType {
  window,
  button,
  edit,
  text,
  menu,
  menuItem,
  tab,
  tabItem,
  list,
  listItem,
  comboBox,
  checkBox,
  radioButton,
  image,
  hyperlink,
  tree,
  treeItem,
  slider,
  progressBar,
  unknown,
}

enum UiPattern {
  invoke,
  value,
  text,
  selection,
  selectionItem,
  toggle,
  expandCollapse,
  scroll,
  rangeValue,
}

/// Platform-neutral, read-only description of an accessible UI element.
final class UiElement {
  UiElement({
    required this.id,
    required this.name,
    required this.controlType,
    required this.isEnabled,
    required this.isVisible,
    required this.isFocused,
    required this.depth,
    this.isPassword = false,
    this.isValueReadOnly,
    this.parentId,
    this.automationId,
    this.className,
    Set<UiPattern> supportedPatterns = const {},
  }) : supportedPatterns = Set.unmodifiable(supportedPatterns);

  final String id;
  final String? parentId;
  final String name;
  final String? automationId;
  final UiControlType controlType;
  final String? className;
  final bool isEnabled;
  final bool isVisible;
  final bool isFocused;
  final bool isPassword;
  final bool? isValueReadOnly;
  final int depth;
  final Set<UiPattern> supportedPatterns;

  Map<String, Object?> toMap() => {
    'id': id,
    'parent_id': parentId,
    'name': name,
    'automation_id': automationId,
    'control_type': controlType.name,
    'class_name': className,
    'is_enabled': isEnabled,
    'is_visible': isVisible,
    'is_focused': isFocused,
    'is_password': isPassword,
    'is_value_read_only': isValueReadOnly,
    'depth': depth,
    'supported_patterns': supportedPatterns
        .map((pattern) => pattern.name)
        .toList(growable: false),
  };

  factory UiElement.fromMap(Map<Object?, Object?> map) => UiElement(
    id: map['id']! as String,
    parentId: map['parent_id'] as String?,
    name: map['name']! as String,
    automationId: map['automation_id'] as String?,
    controlType: UiControlType.values.byName(map['control_type']! as String),
    className: map['class_name'] as String?,
    isEnabled: map['is_enabled']! as bool,
    isVisible: map['is_visible']! as bool,
    isFocused: map['is_focused']! as bool,
    isPassword: map['is_password'] as bool? ?? false,
    isValueReadOnly: map['is_value_read_only'] as bool?,
    depth: map['depth']! as int,
    supportedPatterns: (map['supported_patterns']! as List<Object?>)
        .cast<String>()
        .map(UiPattern.values.byName)
        .toSet(),
  );
}

final class UiInspectionResult {
  UiInspectionResult({
    required this.windowId,
    required List<UiElement> elements,
    required this.maxDepth,
    required this.maxElements,
    required this.wasTruncated,
  }) : elements = List.unmodifiable(elements);

  final String windowId;
  final List<UiElement> elements;
  final int maxDepth;
  final int maxElements;
  final bool wasTruncated;

  UiElement? get rootElement => elements.isEmpty ? null : elements.first;

  Map<String, Object?> toMap() => {
    'window_id': windowId,
    'elements': elements.map((element) => element.toMap()).toList(),
    'element_count': elements.length,
    'max_depth': maxDepth,
    'max_elements': maxElements,
    'was_truncated': wasTruncated,
  };
}
