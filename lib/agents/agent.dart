import '../core/result.dart';
import '../tools/tool.dart';

sealed class AgentRequest {
  const AgentRequest();
}

final class LaunchApplicationAgentRequest extends AgentRequest {
  const LaunchApplicationAgentRequest({required this.applicationId});

  final String applicationId;
}

final class AgentResponse {
  const AgentResponse({required this.message, this.data = const {}});

  final String message;
  final Map<String, Object?> data;
}

abstract interface class Agent {
  String get id;
  String get name;
  String get description;
  List<Tool> get availableTools;

  Future<Result<AgentResponse>> handle(AgentRequest request);
}
