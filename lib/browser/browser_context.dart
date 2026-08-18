import '../tools/windows/discovery/window_info.dart';
import '../tools/windows/ui_automation/ui_element.dart';

enum BrowserApplication { chrome, edge }

final class BrowserContextElement {
  BrowserContextElement({
    required this.id,
    required this.parentId,
    required this.role,
    required this.name,
    required this.depth,
    required this.isPassword,
    required Set<String> supportedPatterns,
  }) : supportedPatterns = Set.unmodifiable(supportedPatterns);

  factory BrowserContextElement.fromUiElement(UiElement element) {
    final isPassword = element.isPassword;
    return BrowserContextElement(
      id: element.id,
      parentId: element.parentId,
      role: isPassword ? 'password' : element.controlType.name,
      name: element.name,
      depth: element.depth,
      isPassword: isPassword,
      supportedPatterns: element.supportedPatterns
          .map((pattern) => pattern.name)
          .toSet(),
    );
  }

  final String id;
  final String? parentId;
  final String role;
  final String name;
  final int depth;
  final bool isPassword;
  final Set<String> supportedPatterns;

  Map<String, Object?> toMap() => {
    'id': id,
    'parent_id': parentId,
    'role': role,
    'name': name,
    'depth': depth,
    'is_password': isPassword,
    'supported_patterns': supportedPatterns.toList(growable: false),
  };
}

final class BrowserContext {
  BrowserContext({
    required this.browser,
    required this.windowId,
    required this.title,
    required List<BrowserContextElement> elements,
    required this.maxDepth,
    required this.maxElements,
    required this.wasTruncated,
  }) : elements = List.unmodifiable(elements);

  final BrowserApplication browser;
  final String windowId;
  final String title;
  final List<BrowserContextElement> elements;
  final int maxDepth;
  final int maxElements;
  final bool wasTruncated;

  Map<String, Object?> toMap() => {
    'browser': browser.name,
    'window_id': windowId,
    'title': title,
    'elements': elements.map((element) => element.toMap()).toList(),
    'element_count': elements.length,
    'max_depth': maxDepth,
    'max_elements': maxElements,
    'was_truncated': wasTruncated,
  };
}

BrowserApplication? browserApplicationFor(WindowInfo window) =>
    switch (window.applicationId) {
      'chrome' => BrowserApplication.chrome,
      'edge' => BrowserApplication.edge,
      _ => null,
    };
