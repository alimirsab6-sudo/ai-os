import 'dart:io';

import 'package:ai_os/app/composition_root.dart';
import 'package:ai_os/browser/chrome/chrome_profile_registry.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/result.dart';

Future<void> main(List<String> arguments) async {
  final selectedIndex = _integerOption(arguments, '--profile-index=');
  final confirmed = arguments.contains('--confirm-launch');
  final services = CompositionRoot.create();
  final orchestrator = services.get<Orchestrator>();
  final discovery = await orchestrator.executeCommand(
    const DiscoverChromeProfilesCommand(),
  );
  if (discovery case Failed(:final failure)) {
    stderr.writeln(failure);
    exitCode = 1;
    return;
  }
  final profiles = services.get<ChromeProfileRegistry>().listProfiles();
  stdout.writeln('Chrome Profiles');
  for (var index = 0; index < profiles.length; index++) {
    final suffix = profiles[index].isDefault ? ' (default)' : '';
    stdout.writeln('[$index] ${profiles[index].displayName}$suffix');
  }
  if (selectedIndex == null) {
    stdout.writeln(
      'Select a profile with --profile-index=N; no launch occurred.',
    );
    return;
  }
  if (selectedIndex < 0 || selectedIndex >= profiles.length) {
    stderr.writeln('Selection is not in the freshly discovered profile list.');
    exitCode = 64;
    return;
  }
  if (!confirmed) {
    stderr.writeln('Add --confirm-launch to launch the selected profile.');
    exitCode = 64;
    return;
  }
  final selected = profiles[selectedIndex];
  final result = await orchestrator.executeCommand(
    LaunchChromeProfileCommand(profileId: selected.id),
  );
  result.fold(
    (response) => stdout.writeln(
      '${response.message} Selected profile: ${selected.displayName}.',
    ),
    (failure) {
      stderr.writeln(failure);
      exitCode = 1;
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
