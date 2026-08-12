import '../core/result.dart';
import '../tools/tool.dart';

final class AgentRequest {
  const AgentRequest({required this.instruction});

  final String instruction;
}

final class AgentResponse {
  const AgentResponse({required this.message});

  final String message;
}

abstract interface class Agent {
  String get id;
  String get name;
  String get description;
  List<Tool> get availableTools;

  Future<Result<AgentResponse>> handle(AgentRequest request);
}
