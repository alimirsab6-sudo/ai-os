import 'dart:io';

import 'package:ai_os/core/result.dart';
import 'package:ai_os/voice/kokoro/kokoro_bridge.dart';
import 'package:ai_os/voice/kokoro/node_kokoro_bridge.dart';

Future<void> main(List<String> arguments) async {
  final root = Directory.current.path;
  final bridge = NodeKokoroBridge(
    launcher: FixedNodeKokoroProcessLauncher(projectRoot: root),
    allowedOutputDirectory:
        '$root${Platform.pathSeparator}runtime${Platform.pathSeparator}kokoro'
        '${Platform.pathSeparator}output${Platform.pathSeparator}bridge',
    diagnostics: stdout.writeln,
  );
  try {
    final initialized = await bridge.initialize();
    if (initialized case Failed<void>(:final failure)) {
      stderr.writeln('${failure.code}: ${failure.message}');
      exitCode = 1;
      return;
    }
    final phrases = arguments.isEmpty
        ? const [
            'Calculator opened successfully.',
            'Notepad opened successfully.',
            'CronyX Browser is ready.',
            'Windows Settings opened successfully.',
          ]
        : arguments;
    for (var index = 0; index < phrases.length; index++) {
      final createdAt = DateTime.now().microsecondsSinceEpoch;
      final stopwatch = Stopwatch()..start();
      final generated = await bridge.synthesize(
        KokoroBridgeRequest(
          id: '${index + 1}',
          text: phrases[index],
          createdAtEpochMicroseconds: createdAt,
        ),
      );
      generated.fold(
        (audio) => stdout.writeln(
          '[TTS:${index + 1}] T0->T6 total_generation '
          '${stopwatch.elapsedMilliseconds} ms; ${audio.filePath}',
        ),
        (failure) {
          stderr.writeln('${failure.code}: ${failure.message}');
          exitCode = 1;
        },
      );
    }
  } finally {
    await bridge.dispose();
  }
}
