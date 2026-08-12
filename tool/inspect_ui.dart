import 'dart:io';

import 'package:ai_os/app/composition_root.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/tools/windows/discovery/window_discovery.dart';
import 'package:ai_os/tools/windows/discovery/window_info.dart';
import 'package:ai_os/tools/windows/ui_automation/ui_automation.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    _usage();
    exitCode = 64;
    return;
  }
  final windowId = arguments.first;
  final maxDepth = arguments.length > 1
      ? int.tryParse(arguments[1])
      : UiTraversalLimits.defaultMaxDepth;
  final maxElements = arguments.length > 2
      ? int.tryParse(arguments[2])
      : UiTraversalLimits.defaultMaxElements;
  if (maxDepth == null ||
      maxDepth < 0 ||
      maxDepth > UiTraversalLimits.maximumDepth ||
      maxElements == null ||
      maxElements < 1 ||
      maxElements > UiTraversalLimits.maximumElements) {
    stderr.writeln('Traversal limits are invalid or exceed safety ceilings.');
    _usage();
    exitCode = 64;
    return;
  }

  final services = CompositionRoot.create();
  final window = await _findDiscoveredWindow(
    services.get<WindowDiscovery>(),
    windowId,
  );
  if (window == null) {
    stderr.writeln('The ID is not in the current discovery snapshot.');
    exitCode = 1;
    return;
  }

  final result = await services.get<Orchestrator>().executeCommand(
    InspectUiCommand(
      windowId: windowId,
      maxDepth: maxDepth,
      maxElements: maxElements,
    ),
  );
  result.fold(
    (response) {
      stdout.writeln('Window:');
      stdout.writeln(window.title);
      stdout.writeln();
      final rawElements = response.data['elements'];
      if (rawElements is List) {
        for (final element in rawElements.whereType<Map<String, Object?>>()) {
          final depth = element['depth']! as int;
          final type = element['control_type']! as String;
          final name = element['name']! as String;
          final automationId = element['automation_id'] as String?;
          final patterns = (element['supported_patterns'] as List?)?.join(', ');
          final details = <String>[
            if (name.isNotEmpty) name,
            if (automationId != null) 'id=$automationId',
            if (patterns != null && patterns.isNotEmpty) 'patterns=$patterns',
          ];
          stdout.writeln(
            '${'  ' * depth}$type${details.isEmpty ? '' : ': ${details.join(' | ')}'}',
          );
        }
      }
      stdout.writeln();
      stdout.writeln(
        'Elements: ${response.data['element_count']} | '
        'Truncated: ${response.data['was_truncated']} | '
        'Limits: depth=$maxDepth, elements=$maxElements',
      );
    },
    (failure) {
      stderr.writeln(failure);
      exitCode = 1;
    },
  );
}

Future<WindowInfo?> _findDiscoveredWindow(
  WindowDiscovery discovery,
  String windowId,
) async {
  final result = await discovery.listWindows();
  return result.fold(
    (windows) {
      for (final window in windows) {
        if (window.id == windowId) return window;
      }
      return null;
    },
    (failure) {
      stderr.writeln(failure);
      return null;
    },
  );
}

void _usage() {
  stderr.writeln(
    'Usage: dart run tool/inspect_ui.dart <discovered-window-id> '
    '[maxDepth 0-${UiTraversalLimits.maximumDepth}] '
    '[maxElements 1-${UiTraversalLimits.maximumElements}]',
  );
}
