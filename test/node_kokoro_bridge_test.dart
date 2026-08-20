import 'package:ai_os/core/result.dart';
import 'package:ai_os/voice/kokoro/kokoro_bridge.dart';
import 'package:ai_os/voice/kokoro/node_kokoro_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/speech_fakes.dart';

void main() {
  const outputDirectory = r'C:\ai-os\runtime\kokoro\output\bridge';

  test('structured bridge request contains only fixed operation and text', () {
    const request = KokoroBridgeRequest(id: '7', text: 'Hello CronyX.');

    expect(request.toJson(), {
      'id': '7',
      'operation': 'synthesize',
      'text': 'Hello CronyX.',
    });
  });

  test('invalid bridge request is rejected before process use', () {
    final invalid = KokoroBridgeRequest.fromJson({
      'id': '../unsafe',
      'operation': 'execute',
      'text': '',
    });

    expect(invalid, isA<Failed<KokoroBridgeRequest>>());
    expect(
      (invalid as Failed<KokoroBridgeRequest>).failure.code,
      'invalid_request',
    );
  });

  test('managed bridge sends JSON and accepts controlled audio path', () async {
    final process = FakeKokoroRuntimeProcess();
    final bridge = NodeKokoroBridge(
      launcher: FakeKokoroRuntimeProcessLauncher.success(process),
      allowedOutputDirectory: outputDirectory,
    );
    final initializing = bridge.initialize();
    await Future<void>.delayed(Duration.zero);
    process.stdoutController.add('{"type":"ready"}');
    expect((await initializing).isSuccess, isTrue);

    final synthesis = bridge.synthesize(
      const KokoroBridgeRequest(id: '1', text: 'Hello.'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(process.lastWrittenJson['operation'], 'synthesize');
    expect(process.lastWrittenJson.containsKey('executable'), isFalse);
    process.stdoutController.add(
      '{"id":"1","ok":true,'
      '"audio_path":"C:\\\\ai-os\\\\runtime\\\\kokoro\\\\output\\\\bridge\\\\speech.wav",'
      '"sample_rate":24000,"channels":1,"bits_per_sample":32,'
      '"timing":{"node_received_epoch_ms":1,"node_queue_ms":2.0,'
      '"inference_ms":3.0,"wav_write_ms":4.0,"node_total_ms":9.0,'
      '"cache_hit":false}}',
    );

    final result = await synthesis;
    expect(result.isSuccess, isTrue);
    expect((result as Success<KokoroAudioArtifact>).value.cacheHit, isFalse);
    await bridge.dispose();
  });

  test('runtime unavailable is reported without starting a shell', () async {
    final bridge = NodeKokoroBridge(
      launcher: FakeKokoroRuntimeProcessLauncher.failure(
        const Failure('Missing.', code: 'kokoro_runtime_unavailable'),
      ),
      allowedOutputDirectory: outputDirectory,
    );

    final result = await bridge.initialize();

    expect(result, isA<Failed<void>>());
    expect((result as Failed<void>).failure.code, 'kokoro_runtime_unavailable');
  });

  test('runtime process exit fails initialization and pending work', () async {
    final process = FakeKokoroRuntimeProcess();
    final bridge = NodeKokoroBridge(
      launcher: FakeKokoroRuntimeProcessLauncher.success(process),
      allowedOutputDirectory: outputDirectory,
    );
    final initializing = bridge.initialize();

    process.exitCompleter.complete(9);
    final result = await initializing;

    expect(result, isA<Failed<void>>());
    expect((result as Failed<void>).failure.code, 'kokoro_process_ended');
    await bridge.dispose();
  });
}

