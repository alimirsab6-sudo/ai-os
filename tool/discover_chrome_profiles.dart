import 'dart:io';

import 'package:ai_os/app/composition_root.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/result.dart';

Future<void> main() async {
  final services = CompositionRoot.create();
  final result = await services.get<Orchestrator>().executeCommand(
    const DiscoverChromeProfilesCommand(),
  );
  if (result case Failed(:final failure)) {
    stderr.writeln(failure);
    exitCode = 1;
    return;
  }
  final profiles =
      ((result as Success).value.data['profiles']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
  stdout.writeln('Chrome Profiles');
  if (profiles.isEmpty) {
    stdout.writeln('No Chrome profiles were discovered.');
    return;
  }
  for (var index = 0; index < profiles.length; index++) {
    final profile = profiles[index];
    stdout.writeln('${index + 1}. ${profile['display_name']}');
    stdout.writeln('   Profile ID: ${profile['profile_id']}');
    if (profile['is_default'] == true) stdout.writeln('   Default: yes');
  }
}
