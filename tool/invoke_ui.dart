import 'dart:io';

import 'package:ai_os/app/composition_root.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/tools/windows/discovery/window_discovery.dart';
import 'package:ai_os/tools/windows/discovery/window_info.dart';
import 'package:ai_os/tools/windows/ui_automation/ui_automation.dart';
import 'package:ai_os/tools/windows/ui_automation/ui_element.dart';

const _blockedNames = {
  'close',
  'delete',
  'remove',
  'uninstall',
  'restart',
  'shut down',
  'sign out',
};

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    _usage();
    exitCode = 64;
    return;
  }
  final windowId = arguments.first;
  final selectedIndex = _integerOption(arguments, '--select-index=');
  final confirmed = arguments.contains('--confirm-invoke');
  final staleTest = arguments.contains('--stale-test');
  final maxDepth = _integerOption(arguments, '--max-depth=') ?? 5;
  final maxElements = _integerOption(arguments, '--max-elements=') ?? 100;
  if (maxDepth < 0 ||
      maxDepth > UiTraversalLimits.maximumDepth ||
      maxElements < 1 ||
      maxElements > UiTraversalLimits.maximumElements) {
    stderr.writeln('Traversal limits are invalid or exceed safety ceilings.');
    exitCode = 64;
    return;
  }

  final services = CompositionRoot.create();
  final window = await _findDiscoveredWindow(
    services.get<WindowDiscovery>(),
    windowId,
  );
  if (window == null) {
    stderr.writeln(
      'The window ID is absent from the current discovery snapshot.',
    );
    exitCode = 1;
    return;
  }

  final orchestrator = services.get<Orchestrator>();
  final inspection = await orchestrator.executeCommand(
    InspectUiCommand(
      windowId: windowId,
      maxDepth: maxDepth,
      maxElements: maxElements,
    ),
  );
  if (inspection case Failed(:final failure)) {
    stderr.writeln(failure);
    exitCode = 1;
    return;
  }
  final inspectionResponse = (inspection as Success).value;
  final elements = (inspectionResponse.data['elements']! as List<Object?>)
      .cast<Map<Object?, Object?>>()
      .map(UiElement.fromMap)
      .where(_isSafeInvokeCandidate)
      .toList(growable: false);

  stdout.writeln('Window: ${window.title}');
  stdout.writeln('Freshly discovered safe Invoke elements:');
  for (var index = 0; index < elements.length; index++) {
    final element = elements[index];
    stdout.writeln(
      '[$index] ${element.controlType.name}: '
      '${element.name.isEmpty ? '(unnamed)' : element.name}',
    );
  }
  if (selectedIndex == null) {
    stdout.writeln('No element selected; no action occurred.');
    return;
  }
  if (selectedIndex < 0 || selectedIndex >= elements.length) {
    stderr.writeln('Selection is not in the freshly discovered list.');
    exitCode = 1;
    return;
  }
  if (!confirmed) {
    stderr.writeln('Add --confirm-invoke to invoke the selected list item.');
    exitCode = 1;
    return;
  }

  final selected = elements[selectedIndex];
  if (staleTest) {
    final refresh = await orchestrator.executeCommand(
      InspectUiCommand(
        windowId: windowId,
        maxDepth: maxDepth,
        maxElements: maxElements,
      ),
    );
    if (refresh.isFailure) {
      stderr.writeln('Could not refresh the tree for the stale-element test.');
      exitCode = 1;
      return;
    }
  }

  final result = await orchestrator.executeCommand(
    InvokeUiElementCommand(windowId: windowId, elementId: selected.id),
  );
  result.fold((response) => stdout.writeln(response.message), (failure) {
    if (staleTest && failure.code == 'stale_ui_element') {
      stdout.writeln('Expected stale-element failure: $failure');
    } else {
      stderr.writeln(failure);
      exitCode = 1;
    }
  });
}

bool _isSafeInvokeCandidate(UiElement element) =>
    element.supportedPatterns.contains(UiPattern.invoke) &&
    !_blockedNames.any(element.name.trim().toLowerCase().contains);

int? _integerOption(List<String> arguments, String prefix) {
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) {
      return int.tryParse(argument.substring(prefix.length));
    }
  }
  return null;
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
    'Usage: dart run tool/invoke_ui.dart <discovered-window-id> '
    '[--max-depth=5] [--max-elements=100] '
    '[--select-index=N --confirm-invoke] [--stale-test]',
  );
}
