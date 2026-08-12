/// Platform-neutral snapshot of a top-level application window.
final class WindowInfo {
  const WindowInfo({
    required this.id,
    required this.title,
    required this.processId,
    required this.isVisible,
    required this.isMinimized,
    required this.isMaximized,
    required this.isActive,
    this.processName,
    this.applicationId,
  });

  final String id;
  final String title;
  final int processId;
  final String? processName;
  final String? applicationId;
  final bool isVisible;
  final bool isMinimized;
  final bool isMaximized;
  final bool isActive;

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'process_id': processId,
    'process_name': processName,
    'application_id': applicationId,
    'is_visible': isVisible,
    'is_minimized': isMinimized,
    'is_maximized': isMaximized,
    'is_active': isActive,
  };
}
