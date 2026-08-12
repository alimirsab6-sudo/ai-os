import '../../agents/agent.dart';
import '../../agents/pc_agent/pc_agent.dart';
import '../../ai/model_provider/model_provider.dart';
import '../../tools/tool.dart';
import '../events/app_event.dart';
import '../events/event_bus.dart';
import '../result.dart';

final class OrchestratorResponse {
  const OrchestratorResponse({
    required this.message,
    this.requestedToolCalls = const [],
  });

  final String message;
  final List<ModelToolCall> requestedToolCalls;
}

sealed class OrchestratorCommand {
  const OrchestratorCommand();
}

final class LaunchApplicationCommand extends OrchestratorCommand {
  const LaunchApplicationCommand({required this.applicationId});

  final String applicationId;
}

/// Coordinates requests while keeping providers, agents, and tools replaceable.
final class Orchestrator {
  Orchestrator({
    required this.modelProvider,
    required this.events,
    List<Agent> agents = const [],
    List<Tool> tools = const [],
  }) : agents = List.unmodifiable(agents),
       tools = List.unmodifiable(tools);

  final ModelProvider modelProvider;
  final EventPublisher events;
  final List<Agent> agents;
  final List<Tool> tools;

  Future<Result<OrchestratorResponse>> handle(String userRequest) async {
    if (userRequest.trim().isEmpty) {
      return const Result.failure(
        Failure('A user request is required.', code: 'empty_request'),
      );
    }
    events.publish(
      ApplicationEvent(
        type: 'orchestrator.request.received',
        occurredAt: DateTime.now().toUtc(),
      ),
    );
    final providerResult = await modelProvider.generate(
      ModelRequest(
        messages: [
          ModelMessage(role: ModelMessageRole.user, content: userRequest),
        ],
        tools: tools.map(_toModelTool).toList(growable: false),
      ),
    );
    return providerResult.fold((response) {
      events.publish(
        ApplicationEvent(
          type: 'orchestrator.response.completed',
          occurredAt: DateTime.now().toUtc(),
        ),
      );
      return Result.success(
        OrchestratorResponse(
          message: response.message.content,
          requestedToolCalls: response.toolCalls,
        ),
      );
    }, Result.failure);
  }

  /// Routes a deterministic command without consulting the model provider.
  Future<Result<OrchestratorResponse>> executeCommand(
    OrchestratorCommand command,
  ) async {
    if (command is! LaunchApplicationCommand) {
      return const Result.failure(
        Failure('Unsupported command.', code: 'unsupported_command'),
      );
    }

    events.publish(
      ApplicationEvent(
        type: 'pc.command.requested',
        occurredAt: DateTime.now().toUtc(),
        data: {
          'command': 'launch_application',
          'application_id': command.applicationId,
        },
      ),
    );

    final pcAgent = _findPcAgent();
    if (pcAgent == null) {
      return const Result.failure(
        Failure('PC Agent is not configured.', code: 'pc_agent_unavailable'),
      );
    }

    final result = await pcAgent.handle(
      LaunchApplicationAgentRequest(applicationId: command.applicationId),
    );
    return result.fold(
      (response) =>
          Result.success(OrchestratorResponse(message: response.message)),
      Result.failure,
    );
  }

  PcAgent? _findPcAgent() {
    for (final agent in agents) {
      if (agent is PcAgent) {
        return agent;
      }
    }
    return null;
  }

  ModelToolDefinition _toModelTool(Tool tool) => ModelToolDefinition(
    id: tool.id,
    name: tool.name,
    description: tool.description,
    inputFields: tool.inputSchema.fields.map(
      (name, field) => MapEntry(name, field.type.name),
    ),
  );
}
