import 'dart:io';

import 'package:ai_os/app/composition_root.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';

/// Development-only, fixed command path for the Milestone 1 manual test.
Future<void> main() async {
  final services = CompositionRoot.create();
  final result = await services.get<Orchestrator>().executeCommand(
    const LaunchApplicationCommand(applicationId: 'chrome'),
  );

  result.fold((response) => stdout.writeln(response.message), (failure) {
    stderr.writeln(failure);
    exitCode = 1;
  });
}
