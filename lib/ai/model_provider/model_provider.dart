import '../../core/result.dart';

enum ModelMessageRole { user, assistant, system, tool }

final class ModelMessage {
  const ModelMessage({required this.role, required this.content});

  final ModelMessageRole role;
  final String content;
}

final class ModelToolDefinition {
  const ModelToolDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.inputFields,
  });

  final String id;
  final String name;
  final String description;
  final Map<String, String> inputFields;
}

final class ModelRequest {
  const ModelRequest({required this.messages, this.tools = const []});

  final List<ModelMessage> messages;
  final List<ModelToolDefinition> tools;
}

final class ModelToolCall {
  const ModelToolCall({
    required this.id,
    required this.toolId,
    required this.arguments,
  });

  final String id;
  final String toolId;
  final Map<String, Object?> arguments;
}

final class ModelResponse {
  const ModelResponse({required this.message, this.toolCalls = const []});

  final ModelMessage message;
  final List<ModelToolCall> toolCalls;
}

abstract interface class ModelProvider {
  String get id;

  Future<Result<ModelResponse>> generate(ModelRequest request);
}

