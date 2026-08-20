import 'package:ai_os/tools/windows/discovery/window_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WindowInfo exposes a platform-neutral structured representation', () {
    const window = WindowInfo(
      id: 'windows:window:abc',
      title: 'Editor',
      processId: 10,
      processName: 'editor.exe',
      applicationId: 'editor',
      isVisible: true,
      isMinimized: false,
      isMaximized: false,
      isActive: true,
    );

    expect(window.id, 'windows:window:abc');
    expect(window.toMap(), {
      'id': 'windows:window:abc',
      'title': 'Editor',
      'process_id': 10,
      'process_name': 'editor.exe',
      'application_id': 'editor',
      'is_visible': true,
      'is_minimized': false,
      'is_maximized': false,
      'is_active': true,
    });
  });
}

