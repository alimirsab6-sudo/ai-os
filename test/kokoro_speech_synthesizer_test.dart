import 'dart:async';

import 'package:ai_os/core/events/app_event.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/voice/kokoro/kokoro_speech_synthesizer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/speech_fakes.dart';

void main() {
  late EventBus events;
  late FakeKokoroBridge bridge;
  late FakeSpeechAudioPlayer audio;
  late List<ApplicationEvent> emitted;
  late StreamSubscription subscription;

  setUp(() {
    events = EventBus();
    bridge = FakeKokoroBridge();
    audio = FakeSpeechAudioPlayer();
    emitted = [];
    subscription = events.events
        .where((event) => event is ApplicationEvent)
        .cast<ApplicationEvent>()
        .listen(emitted.add);
  });

  tearDown(() async {
    await subscription.cancel();
    await events.close();
  });

  KokoroSpeechSynthesizer createSynthesizer() => KokoroSpeechSynthesizer(
    bridge: bridge,
    audioPlayer: audio,
    events: events,
  );

  test('successful speak generates and plays af_bella audio', () async {
    final synthesizer = createSynthesizer();

    final result = await synthesizer.speak('The browser is open.');

    expect(result.isSuccess, isTrue);
    expect(bridge.requests.single.text, 'The browser is open.');
    expect(audio.playCount, 1);
    expect(
      emitted.map((event) => event.type),
      containsAllInOrder([
        'tts.runtime.ready',
        'tts.generation.started',
        'tts.playback.started',
        'tts.playback.completed',
      ]),
    );
  });

  test(
    'TTS generation failure is structured and emits voice failure',
    () async {
      bridge.synthesisFailure = const Failure(
        'Runtime failed.',
        code: 'synthesis_failed',
      );
      final synthesizer = createSynthesizer();

      final result = await synthesizer.speak('Speak this.');

      expect(result, isA<Failed<void>>());
      expect((result as Failed<void>).failure.code, 'synthesis_failed');
      expect(audio.playCount, 0);
      expect(emitted.last.type, 'tts.failed');
      expect(emitted.last.data['stage'], 'generation');
    },
  );

  test('playback failure is structured and emits playback failure', () async {
    audio.playFailure = const Failure('Decoder failed.', code: 'audio_failed');
    final synthesizer = createSynthesizer();

    final result = await synthesizer.speak('Speak this.');

    expect(result, isA<Failed<void>>());
    expect((result as Failed<void>).failure.code, 'audio_failed');
    expect(emitted.last.type, 'tts.failed');
    expect(emitted.last.data['stage'], 'playback');
    expect(emitted.last.data['failure_code'], 'audio_failed');
  });

  test('stop interrupts active playback', () async {
    audio = FakeSpeechAudioPlayer(autoComplete: false);
    final synthesizer = createSynthesizer();
    final speaking = synthesizer.speak('Keep speaking.');
    await Future<void>.delayed(Duration.zero);

    await synthesizer.stop();
    final result = await speaking;

    expect(result, isA<Failed<void>>());
    expect((result as Failed<void>).failure.code, 'speech_stopped');
    expect(
      emitted.map((event) => event.type),
      contains('tts.playback.stopped'),
    );
  });

  test('dispose releases player and persistent bridge', () async {
    final synthesizer = createSynthesizer();
    await synthesizer.initialize();

    await synthesizer.dispose();

    expect(audio.disposeCount, 1);
    expect(bridge.disposeCount, 1);
    expect(emitted.last.type, 'tts.disposed');
  });

  test('a new request stops previous speech before playback', () async {
    audio = FakeSpeechAudioPlayer(autoComplete: false);
    final synthesizer = createSynthesizer();
    final first = synthesizer.speak('First response.');
    await Future<void>.delayed(Duration.zero);

    final second = synthesizer.speak('Second response.');
    await Future<void>.delayed(Duration.zero);
    audio.complete();

    final firstResult = await first;
    final secondResult = await second;
    expect(firstResult, isA<Failed<void>>());
    expect(secondResult.isSuccess, isTrue);
    expect(audio.maximumConcurrentPlaybacks, 1);
    expect(bridge.requests.map((request) => request.text), [
      'First response.',
      'Second response.',
    ]);
  });
}
