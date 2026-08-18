import 'package:ai_os/agents/voice_agent/voice_agent.dart';
import 'package:ai_os/ai/model_provider/mock_model_provider.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/voice/assistant/voice_assistant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'existing interpreter recognizes controlled enrollment and reset commands',
    () {
      const interpreter = DeterministicCommandInterpreter();

      final enrollment = interpreter.interpret('Enroll my voice as Ali');
      final reset = interpreter.interpret('Reset voice profile');
      final activity = interpreter.interpret('What did they do?');

      expect(
        (enrollment as Success<OrchestratorCommand>).value,
        isA<EnrollOwnerVoiceCommand>(),
      );
      expect(
        ((enrollment.value as EnrollOwnerVoiceCommand).displayName),
        'Ali',
      );
      expect(
        (reset as Success<OrchestratorCommand>).value,
        isA<ResetOwnerVoiceProfileCommand>(),
      );
      expect(
        (activity as Success<OrchestratorCommand>).value,
        isA<DescribeVoiceSecurityActivityCommand>(),
      );
    },
  );

  test(
    'enrollment routes through Orchestrator to the existing agent pipeline',
    () async {
      final events = EventBus();
      final assistant = FakeVoiceAssistant();
      final orchestrator = Orchestrator(
        modelProvider: const MockModelProvider(),
        events: events,
        agents: [VoiceAgent(assistant: assistant)],
        commandInterpreter: const DeterministicCommandInterpreter(),
      );

      final result = await orchestrator.handle('Enroll voice as Ali');

      expect(result.isSuccess, isTrue);
      expect(assistant.enrolledName, 'Ali');
      await events.close();
    },
  );

  test(
    'voice security status remains locked without owner verification',
    () async {
      final events = EventBus();
      final assistant = FakeVoiceAssistant()..verified = false;
      final orchestrator = Orchestrator(
        modelProvider: const MockModelProvider(),
        events: events,
        agents: [VoiceAgent(assistant: assistant)],
        commandInterpreter: const DeterministicCommandInterpreter(),
      );

      final result = await orchestrator.handle('What happened?');

      expect(
        (result as Failed<OrchestratorResponse>).failure.code,
        'voice_locked',
      );
      await events.close();
    },
  );
}

final class FakeVoiceAssistant implements VoiceAssistant {
  String? enrolledName;
  bool verified = false;

  @override
  bool get hasOwnerProfile => enrolledName != null;

  @override
  bool get ownerVerified => verified;

  @override
  bool get wakeMonitoring => false;

  @override
  Future<Result<void>> initialize() async => const Result.success(null);

  @override
  Future<Result<void>> enrollOwner(String displayName) async {
    enrolledName = displayName;
    return const Result.success(null);
  }

  @override
  Future<Result<void>> resetOwnerProfile() async {
    enrolledName = null;
    return const Result.success(null);
  }

  @override
  Future<Result<String>> describeSecurityActivity() async => verified
      ? const Result.success('No activity.')
      : const Result.failure(
          Failure('Voice access is locked.', code: 'voice_locked'),
        );

  @override
  Future<Result<void>> startWakeMonitoring() async =>
      const Result.success(null);

  @override
  Future<Result<void>> stopListening() async => const Result.success(null);

  @override
  Future<void> dispose() async {}
}
