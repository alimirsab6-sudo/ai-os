import 'dart:async';
import 'dart:io';

import 'package:ai_os/core/events/app_event.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/voice/assistant/local_voice_assistant.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/speech_fakes.dart';
import 'support/voice_fakes.dart';

void main() {
  late EventBus events;
  late FakeMicrophoneCapture microphone;
  late FakeLocalVoiceRuntime runtime;
  late MemoryOwnerProfileRepository profiles;
  late FakeSpeechSynthesizer speech;
  late List<ApplicationEvent> emitted;
  late StreamSubscription subscription;
  late int commandCount;
  late List<LocalVoiceAssistant> assistants;

  setUp(() {
    events = EventBus();
    microphone = FakeMicrophoneCapture();
    runtime = FakeLocalVoiceRuntime();
    profiles = MemoryOwnerProfileRepository();
    speech = FakeSpeechSynthesizer(events: events, completeImmediately: true);
    emitted = [];
    commandCount = 0;
    assistants = [];
    subscription = events.events
        .where((event) => event is ApplicationEvent)
        .cast<ApplicationEvent>()
        .listen(emitted.add);
  });

  tearDown(() async {
    for (final assistant in assistants) {
      await assistant.dispose();
    }
    await subscription.cancel();
    await events.close();
  });

  LocalVoiceAssistant createAssistant({DateTime Function()? clock}) {
    final assistant = LocalVoiceAssistant(
      microphone: microphone,
      runtime: runtime,
      profiles: profiles,
      speech: speech,
      events: events,
      lifecycleEvents: events.events,
      clock: clock,
      commandHandler: (transcript) async {
        commandCount++;
        return Result.success(
          OrchestratorResponse(
            message: transcript == 'Open example.com'
                ? 'example.com is opening in CronyX Browser.'
                : '$transcript completed',
          ),
        );
      },
    );
    assistants.add(assistant);
    return assistant;
  }

  Future<ApplicationEvent> waitFor(String type) {
    final existing = emitted.where((event) => event.type == type);
    if (existing.isNotEmpty) return Future.value(existing.last);
    return events.events
        .where((event) => event is ApplicationEvent && event.type == type)
        .cast<ApplicationEvent>()
        .first;
  }

  Future<void> waitForCount(String type, int count) async {
    if (emitted.where((event) => event.type == type).length >= count) return;
    await events.events.firstWhere(
      (event) =>
          event.type == type &&
          emitted.where((item) => item.type == type).length >= count,
    );
  }

  test('keyword configuration activates on Crony without requiring X', () {
    final keywords = File(
      'runtime/voice/config/keywords.txt',
    ).readAsLinesSync();

    expect(keywords, ['K R OW1 N IY0 @CRONY']);
    expect(keywords, everyElement(isNot(startsWith('HH EY1 '))));
  });

  test('startup performs real runtime, TTS, and microphone checks', () async {
    final assistant = createAssistant();

    final result = await assistant.initialize();

    expect(result.isSuccess, isTrue);
    expect(runtime.initializeCount, 1);
    expect(speech.initializeCount, 1);
    expect(microphone.startCount, 1);
    expect(microphone.stopCount, 1);
    expect(
      emitted.map((event) => event.type),
      contains('voice.startup.readiness'),
    );
    expect(
      emitted.map((event) => event.type),
      contains('voice.enrollment.required'),
    );
  });

  test(
    'startup reports STT/runtime failure and does not claim readiness',
    () async {
      runtime.initializeResult = const Result.failure(
        Failure('missing', code: 'voice_models_missing'),
      );
      final assistant = createAssistant();

      final result = await assistant.initialize();

      expect(result.isFailure, isTrue);
      final readiness = emitted.singleWhere(
        (event) => event.type == 'voice.startup.readiness',
      );
      expect(readiness.data['stt'], isFalse);
      expect(readiness.data['speaker_verification'], isFalse);
    },
  );

  test('microphone failure is structured', () async {
    microphone.startFailure = const Failure(
      'denied',
      code: 'microphone_permission_denied',
    );
    final result = await createAssistant().initialize();
    expect((result as Failed<void>).failure.code, 'microphone_failed');
  });

  test(
    'three enrollment samples create one centroid profile without raw audio',
    () async {
      microphone.recordings.addAll([
        [],
        utterance(),
        utterance(),
        utterance(),
        [],
      ]);
      runtime.embeddings.addAll([
        Result.success(unitEmbedding()),
        Result.success(unitEmbedding()),
        Result.success(unitEmbedding()),
      ]);
      final assistant = createAssistant();

      final result = await assistant.enrollOwner('Ali');

      expect(result.isSuccess, isTrue);
      expect(profiles.saveCount, 1);
      expect(profiles.profile?.displayName, 'Ali');
      expect(profiles.profile?.embedding.length, 256);
      expect(runtime.embeddingCount, 3);
      expect(speech.spokenTexts.length, 4);
      expect(assistant.wakeMonitoring, isTrue);
    },
  );

  test('invalid owner name is rejected before microphone use', () async {
    final result = await createAssistant().enrollOwner('   ');
    expect((result as Failed<void>).failure.code, 'invalid_owner_name');
    expect(microphone.startCount, 0);
  });

  test('profile reset stops capture and removes local profile', () async {
    profiles.profile = ownerProfile();
    microphone.recordings.addAll([[], []]);
    final assistant = createAssistant();
    await assistant.initialize();

    final result = await assistant.resetOwnerProfile();

    expect(result.isSuccess, isTrue);
    expect(profiles.profile, isNull);
    expect(profiles.resetCount, 1);
    expect(assistant.ownerVerified, isFalse);
  });

  test(
    'known speaker after wake may execute through command handler',
    () async {
      profiles.profile = ownerProfile();
      microphone.recordings.addAll([[], utterance(), utterance(), []]);
      runtime.wakeResults.add(const Result.success(true));
      runtime.embeddings.add(Result.success(unitEmbedding()));
      runtime.transcripts.addAll([
        const Result.success('Crony'),
        const Result.success('Open Calculator'),
      ]);
      final assistant = createAssistant();

      await assistant.initialize();
      await waitFor('voice.transcript.ready');
      await waitForCount('voice.wake.monitoring.started', 2);

      expect(commandCount, 1);
      expect(
        runtime.wakeCount,
        2,
        reason:
            'the complete wake utterance is evaluated before command capture',
      );
      expect(
        emitted.map((event) => event.type),
        contains('voice.owner.verified'),
      );
      expect(
        speech.spokenTexts,
        contains('Hey Ali, what can I do for you today?'),
      );
      expect(speech.spokenTexts, contains('Open Calculator completed'));
    },
  );

  test(
    'exact local STT fallback activates when keyword scoring misses',
    () async {
      profiles.profile = ownerProfile();
      microphone.recordings.addAll([[], utterance(), utterance(), []]);
      runtime.wakeResults.addAll([
        const Result.success(false),
        const Result.success(false),
      ]);
      runtime.transcripts.addAll([
        const Result.success('Crony.'),
        const Result.success('Open Notepad'),
      ]);
      runtime.embeddings.add(Result.success(unitEmbedding()));
      final assistant = createAssistant();

      await assistant.initialize();
      await waitFor('voice.wake.fallback_detected');
      await waitFor('voice.transcript.ready');
      await waitForCount('voice.wake.monitoring.started', 2);

      expect(commandCount, 1);
      expect(speech.spokenTexts, contains('Open Notepad completed'));
    },
  );

  test(
    'accented wake and command in one utterance execute after verification',
    () async {
      profiles.profile = ownerProfile();
      microphone.recordings.addAll([[], utterance(), []]);
      runtime.wakeResults.addAll([
        const Result.success(false),
        const Result.success(false),
      ]);
      runtime.transcripts.add(
        const Result.success('Coney, can you open the browser?'),
      );
      runtime.embeddings.add(Result.success(unitEmbedding()));
      final assistant = createAssistant();

      await assistant.initialize();
      await waitFor('voice.wake.fallback_detected');
      await waitFor('voice.transcript.ready');
      await waitForCount('voice.wake.monitoring.started', 2);

      expect(commandCount, 1);
      expect(
        emitted
            .singleWhere((event) => event.type == 'voice.transcript.ready')
            .data['transcript'],
        'can you open the browser',
      );
    },
  );

  test(
    'dynamic browser result uses a stable cacheable spoken response',
    () async {
      profiles.profile = ownerProfile();
      microphone.recordings.addAll([[], utterance(), utterance(), []]);
      runtime.wakeResults.add(const Result.success(true));
      runtime.embeddings.add(Result.success(unitEmbedding()));
      runtime.transcripts.addAll([
        const Result.success('Crony'),
        const Result.success('Open example.com'),
      ]);
      final assistant = createAssistant();

      await assistant.initialize();
      await waitFor('voice.transcript.ready');
      await waitForCount('voice.wake.monitoring.started', 2);

      expect(commandCount, 1);
      expect(
        speech.spokenTexts,
        contains('The page is opening in CronyX Browser.'),
      );
    },
  );

  test(
    'unknown speaker remains locked and cannot bypass using owner name',
    () async {
      profiles.profile = ownerProfile();
      microphone.recordings.addAll([[], utterance(), utterance(), []]);
      runtime.wakeResults.add(const Result.success(true));
      runtime.embeddings.add(Result.success(unitEmbedding(1)));
      runtime.transcripts.addAll([
        const Result.success('Crony'),
        const Result.success('Ali'),
      ]);
      final assistant = createAssistant();

      await assistant.initialize();
      final locked = await waitFor('voice.access.locked');
      await waitForCount('voice.wake.monitoring.started', 2);

      expect(locked.data['session_event_id'], isNotNull);
      expect(commandCount, 0);
      expect(assistant.ownerVerified, isFalse);
      expect(speech.spokenTexts.last, contains('remain locked'));
    },
  );

  test('uncertain speaker below conservative threshold is rejected', () async {
    profiles.profile = ownerProfile();
    microphone.recordings.addAll([[], utterance(), utterance(), []]);
    runtime.wakeResults.add(const Result.success(true));
    final uncertain = unitEmbedding();
    uncertain[0] = .74;
    uncertain[1] = .673;
    runtime.embeddings.add(Result.success(uncertain));
    final assistant = createAssistant();

    await assistant.initialize();
    await waitFor('voice.access.locked');
    await waitForCount('voice.wake.monitoring.started', 2);

    expect(commandCount, 0);
    expect(LocalVoiceAssistant.verificationThreshold, .75);
  });

  test('owner return acknowledges an unknown event exactly once', () async {
    profiles.profile = ownerProfile();
    microphone.recordings.addAll([
      [],
      utterance(),
      utterance(),
      utterance(),
      utterance(),
      utterance(),
      utterance(),
      [],
    ]);
    runtime.wakeResults.addAll([
      const Result.success(true),
      const Result.success(true),
      const Result.success(true),
    ]);
    runtime.embeddings.addAll([
      Result.success(unitEmbedding(1)),
      Result.success(unitEmbedding()),
      Result.success(unitEmbedding()),
    ]);
    runtime.transcripts.addAll([
      const Result.success('Crony'),
      const Result.success('John'),
      const Result.success('Crony'),
      const Result.success('Open Calculator'),
      const Result.success('Crony'),
      const Result.success('Open Calculator'),
    ]);
    final assistant = createAssistant();

    await assistant.initialize();
    await waitFor('voice.access.locked');
    await waitFor('voice.security.events.acknowledged');
    await waitForCount('voice.wake.monitoring.started', 4);

    expect(
      speech.spokenTexts
          .where((text) => text.contains('Also, I detected'))
          .length,
      1,
    );
    expect(
      speech.spokenTexts,
      contains('Hey Ali, what can I do for you today?'),
    );
    expect(
      speech.spokenTexts.where((text) => text.contains('welcome back')),
      isEmpty,
    );
  });

  test('security activity is inaccessible while voice is locked', () async {
    final result = await createAssistant().describeSecurityActivity();
    expect((result as Failed<String>).failure.code, 'voice_locked');
  });

  test('startup greeting uses local time and happens once', () async {
    profiles.profile = ownerProfile();
    microphone.recordings.addAll([[], []]);
    final assistant = createAssistant(clock: () => DateTime(2026, 8, 18, 19));

    await assistant.initialize();
    await assistant.initialize();

    expect(
      speech.spokenTexts
          .where((text) => text.startsWith('Good evening, Ali'))
          .length,
      1,
    );
  });

  test('empty STT transcript never executes a command', () async {
    profiles.profile = ownerProfile();
    microphone.recordings.addAll([[], utterance(), utterance(), []]);
    runtime.wakeResults.add(const Result.success(true));
    runtime.embeddings.add(Result.success(unitEmbedding()));
    runtime.transcripts.addAll([
      const Result.success('Crony'),
      const Result.success(''),
    ]);
    final assistant = createAssistant();

    await assistant.initialize();
    await waitFor('voice.stt.empty');
    await waitForCount('voice.wake.monitoring.started', 2);

    expect(commandCount, 0);
  });

  test('STT failure is emitted and command remains blocked', () async {
    profiles.profile = ownerProfile();
    microphone.recordings.addAll([[], utterance(), utterance(), []]);
    runtime.wakeResults.add(const Result.success(true));
    runtime.embeddings.add(Result.success(unitEmbedding()));
    runtime.transcripts.addAll([
      const Result.success('Crony'),
      const Result.failure(Failure('failed', code: 'stt_failed')),
    ]);
    final assistant = createAssistant();

    await assistant.initialize();
    await waitFor('voice.stt.failed');
    await waitForCount('voice.wake.monitoring.started', 2);

    expect(commandCount, 0);
  });

  test('dispose stops microphone and releases runtime resources', () async {
    final assistant = createAssistant();
    await assistant.initialize();

    await assistant.dispose();

    expect(microphone.disposeCount, 1);
    expect(runtime.disposeCount, 1);
    expect(assistant.ownerVerified, isFalse);
  });

  test(
    'real TTS playback pauses wake capture and resumes after completion',
    () async {
      profiles.profile = ownerProfile();
      microphone.recordings.addAll([[], [], []]);
      final assistant = createAssistant();
      await assistant.initialize();
      final startsBeforeSpeech = microphone.startCount;

      await speech.speak('External command response.');
      await waitForCount('voice.wake.monitoring.started', 2);

      expect(microphone.stopCount, greaterThanOrEqualTo(2));
      expect(microphone.startCount, startsBeforeSpeech + 1);
      expect(assistant.wakeMonitoring, isTrue);
    },
  );

  test(
    'unexpected microphone stream completion restarts wake monitoring',
    () async {
      profiles.profile = ownerProfile();
      microphone.recordings.addAll([[], [], []]);
      final assistant = createAssistant();
      await assistant.initialize();

      await microphone.closeActiveStreamUnexpectedly();
      await waitFor('voice.microphone.failed');
      await waitForCount('voice.wake.monitoring.started', 2);

      expect(microphone.startCount, 3);
      expect(assistant.wakeMonitoring, isTrue);
    },
  );
}
