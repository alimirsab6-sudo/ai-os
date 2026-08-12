import 'dart:io';

import 'package:ai_os/app/composition_root.dart';
import 'package:ai_os/core/configuration/app_configuration.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/windows/discovery/window_discovery.dart';
import 'package:ai_os/tools/windows/ui_automation/ui_automation.dart';
import 'package:ai_os/tools/windows/ui_automation/ui_element.dart';

Future<void> main(List<String> arguments) async {
  final windowIndex = _integerOption(arguments, '--window-index=');
  final elementIndex = _integerOption(arguments, '--element-index=');
  final staleTest = arguments.contains('--stale-test');
  final maxDepth = _integerOption(arguments, '--max-depth=') ?? 6;
  final maxElements = _integerOption(arguments, '--max-elements=') ?? 200;
  if (maxDepth < 0 ||
      maxDepth > UiTraversalLimits.maximumDepth ||
      maxElements < 1 ||
      maxElements > UiTraversalLimits.maximumElements) {
    stderr.writeln('Traversal limits are invalid or exceed safety ceilings.');
    exitCode = 64;
    return;
  }

  final configuration = AppConfiguration(
    selectedModelProvider: 'mock',
    permissions: const {Permission.read, Permission.write},
  );
  final services = CompositionRoot.create(configuration: configuration);
  final discoveryResult = await services.get<WindowDiscovery>().listWindows();
  if (discoveryResult case Failed(:final failure)) {
    stderr.writeln(failure);
    exitCode = 1;
    return;
  }
  final windows = (discoveryResult as Success).value;
  stdout.writeln('Discovered windows:');
  for (var index = 0; index < windows.length; index++) {
    stdout.writeln('[$index] ${windows[index].title}');
  }
  if (windowIndex == null) {
    stdout.writeln(
      'Select a window with --window-index=N; no action occurred.',
    );
    return;
  }
  if (windowIndex < 0 || windowIndex >= windows.length) {
    stderr.writeln('Window selection is not in the discovered list.');
    exitCode = 1;
    return;
  }

  final window = windows[windowIndex];
  final orchestrator = services.get<Orchestrator>();
  final inspection = await orchestrator.executeCommand(
    InspectUiCommand(
      windowId: window.id,
      maxDepth: maxDepth,
      maxElements: maxElements,
    ),
  );
  if (inspection case Failed(:final failure)) {
    stderr.writeln(failure);
    exitCode = 1;
    return;
  }
  final elements =
      ((inspection as Success).value.data['elements']! as List<Object?>)
          .cast<Map<Object?, Object?>>()
          .map(UiElement.fromMap)
          .where(
            (element) =>
                element.supportedPatterns.contains(UiPattern.value) &&
                !element.isPassword,
          )
          .toList(growable: false);

  stdout.writeln('Value elements in: ${window.title}');
  for (var index = 0; index < elements.length; index++) {
    final element = elements[index];
    stdout.writeln(
      '[$index] name=${element.name.isEmpty ? '(unnamed)' : element.name}; '
      'type=${element.controlType.name}; '
      'automationId=${element.automationId ?? '(none)'}; '
      'readOnly=${element.isValueReadOnly ?? 'unknown'}',
    );
  }
  if (elementIndex == null) {
    stdout.writeln(
      'Select an element with --element-index=N; no action occurred.',
    );
    return;
  }
  if (elementIndex < 0 || elementIndex >= elements.length) {
    stderr.writeln('Element selection is not in the freshly discovered list.');
    exitCode = 1;
    return;
  }

  final selected = elements[elementIndex];
  stdout.write('Set the selected element value? Type YES to confirm: ');
  if (stdin.readLineSync() != 'YES') {
    stdout.writeln('Cancelled; no value was requested or changed.');
    return;
  }
  stdout.write('Enter the new value: ');
  final value = stdin.readLineSync();
  if (value == null || value.isEmpty) {
    stderr.writeln('A non-empty value is required; no action occurred.');
    exitCode = 64;
    return;
  }
  if (value.length > UiValueLimits.maximumCodeUnits) {
    stderr.writeln('The entered value exceeds the supported size limit.');
    exitCode = 64;
    return;
  }

  if (staleTest) {
    final refresh = await orchestrator.executeCommand(
      InspectUiCommand(
        windowId: window.id,
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
    SetUiElementValueCommand(
      windowId: window.id,
      elementId: selected.id,
      value: value,
    ),
  );
  result.fold(
    (response) {
      stdout.writeln(response.message);
      stdout.writeln('The entered value was not printed or logged.');
    },
    (failure) {
      if (staleTest && failure.code == 'stale_ui_element') {
        stdout.writeln('Expected stale-element failure: $failure');
      } else {
        stderr.writeln(failure);
        exitCode = 1;
      }
    },
  );
}

int? _integerOption(List<String> arguments, String prefix) {
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) {
      return int.tryParse(argument.substring(prefix.length));
    }
  }
  return null;
}
