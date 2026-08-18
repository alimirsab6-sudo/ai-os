import '../../core/result.dart';
import '../../tools/tool.dart';
import '../../voice/assistant/voice_assistant.dart';
import '../agent.dart';

final class VoiceAgent implements Agent {
  const VoiceAgent({required this.assistant});

  final VoiceAssistant assistant;

  @override
  String get id => 'agent.voice';

  @override
  String get name => 'Voice Agent';

  @override
  String get description => 'Manages local owner voice enrollment and access.';

  @override
  List<Tool> get availableTools => const [];

  @override
  Future<Result<AgentResponse>> handle(AgentRequest request) async {
    if (request is EnrollOwnerVoiceAgentRequest) {
      final result = await assistant.enrollOwner(request.displayName);
      return result.fold(
        (_) => Result.success(
          AgentResponse(
            message: '${request.displayName} voice enrollment is complete.',
          ),
        ),
        Result.failure,
      );
    }
    if (request is ResetOwnerVoiceProfileAgentRequest) {
      final result = await assistant.resetOwnerProfile();
      return result.fold(
        (_) => const Result.success(
          AgentResponse(message: 'The owner voice profile has been reset.'),
        ),
        Result.failure,
      );
    }
    if (request is DescribeVoiceSecurityActivityAgentRequest) {
      final result = await assistant.describeSecurityActivity();
      return result.fold(
        (message) => Result.success(AgentResponse(message: message)),
        Result.failure,
      );
    }
    return const Result.failure(
      Failure('Unsupported voice command.', code: 'unsupported_voice_command'),
    );
  }
}
