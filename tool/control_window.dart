import 'dart:io';

import 'package:ai_os/app/composition_root.dart';
import 'package:ai_os/core/configuration/app_configuration.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/windows/control/window_controller.dart';
import 'package:ai_os/tools/windows/discovery/window_discovery.dart';
import 'package:ai_os/tools/windows/discovery/window_info.dart';

/// Development-only controller for a runtime ID from the live discovery list.
Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    _usage();
    exitCode = 64;
    return;
  }

  final operation = WindowOperation.values.where(
    (candidate) => candidate.name == arguments[0].toLowerCase(),
  );
  if (operation.isEmpty) {
    stderr.writeln('Unsupported operation: ${arguments[0]}');
    _usage();
    exitCode = 64;
    return;
  }

  final selectedOperation = operation.single;
  final windowId = arguments[1];
  final defaultServices = CompositionRoot.create();
  final target = await _findDiscoveredWindow(
    defaultServices.get<WindowDiscovery>(),
    windowId,
  );
  if (target == null) {
    stderr.writeln('The supplied ID is not in the current discovery snapshot.');
    exitCode = 1;
    return;
  }

  var services = defaultServices;
  if (selectedOperation == WindowOperation.close) {
    final explicitlyConfirmed = arguments.contains('--confirm-test-window');
    final isNotepad = target.processName?.toLowerCase() == 'notepad.exe';
    if (!explicitlyConfirmed || !isNotepad) {
      stderr.writeln(
        'Close is restricted to a discovered notepad.exe test window and '
        'requires --confirm-test-window.',
      );
      exitCode = 1;
      return;
    }
    services = CompositionRoot.create(
      configuration: AppConfiguration(
        selectedModelProvider: 'mock',
        permissions: {
          Permission.read,
          Permission.execute,
          Permission.sensitive,
        },
      ),
    );
  }

  final command = switch (selectedOperation) {
    WindowOperation.activate => ActivateWindowCommand(windowId: windowId),
    WindowOperation.minimize => MinimizeWindowCommand(windowId: windowId),
    WindowOperation.maximize => MaximizeWindowCommand(windowId: windowId),
    WindowOperation.restore => RestoreWindowCommand(windowId: windowId),
    WindowOperation.close => CloseWindowCommand(windowId: windowId),
  };
  final result = await services.get<Orchestrator>().executeCommand(command);
  result.fold((response) => stdout.writeln(response.message), (failure) {
    stderr.writeln(failure);
    exitCode = 1;
  });
}

Future<WindowInfo?> _findDiscoveredWindow(
  WindowDiscovery discovery,
  String windowId,
) async {
  final result = await discovery.listWindows();
  return result.fold(
    (windows) {
      for (final window in windows) {
        if (window.id == windowId) {
          return window;
        }
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
    'Usage: dart run tool/control_window.dart '
    '<activate|minimize|maximize|restore|close> <discovered-window-id> '
    '[--confirm-test-window]',
  );
}
