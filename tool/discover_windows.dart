import 'dart:io';

import 'package:ai_os/app/composition_root.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';

/// Development-only, read-only desktop discovery command for Milestone 2A.
Future<void> main() async {
  final services = CompositionRoot.create();
  final orchestrator = services.get<Orchestrator>();
  final activeResult = await orchestrator.executeCommand(
    const GetActiveWindowCommand(),
  );
  final windowsResult = await orchestrator.executeCommand(
    const ListWindowsCommand(),
  );

  stdout.writeln('Windows Desktop State');
  stdout.writeln();
  stdout.writeln('Active:');
  activeResult.fold(
    (response) {
      final window = response.data['window'];
      stdout.writeln(
        window is Map<String, Object?> ? _label(window) : '(none)',
      );
    },
    (failure) {
      stderr.writeln(failure);
      exitCode = 1;
    },
  );

  stdout.writeln();
  stdout.writeln('Windows:');
  windowsResult.fold(
    (response) {
      final windows = response.data['windows'];
      if (windows is! List || windows.isEmpty) {
        stdout.writeln('- (none)');
        return;
      }
      for (final window in windows.whereType<Map<String, Object?>>()) {
        stdout.writeln('- ${_label(window)}');
      }
    },
    (failure) {
      stderr.writeln(failure);
      exitCode = 1;
    },
  );
}

String _label(Map<String, Object?> window) {
  final title = window['title'] as String? ?? '(untitled)';
  final processName = window['process_name'] as String?;
  return processName == null ? title : '$title [$processName]';
}
