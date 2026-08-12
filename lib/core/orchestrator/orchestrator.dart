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
    this.data = const {},
  });

  final String message;
  final List<ModelToolCall> requestedToolCalls;
  final Map<String, Object?> data;
}

sealed class OrchestratorCommand {
  const OrchestratorCommand();
}

final class LaunchApplicationCommand extends OrchestratorCommand {
  const LaunchApplicationCommand({required this.applicationId});

  final String applicationId;
}

final class ListWindowsCommand extends OrchestratorCommand {
  const ListWindowsCommand();
}

final class GetActiveWindowCommand extends OrchestratorCommand {
  const GetActiveWindowCommand();
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
    final AgentRequest agentRequest;
    switch (command) {
      case LaunchApplicationCommand(:final applicationId):
        agentRequest = LaunchApplicationAgentRequest(
          applicationId: applicationId,
        );
        events.publish(
          ApplicationEvent(
            type: 'pc.command.requested',
            occurredAt: DateTime.now().toUtc(),
            data: {
              'command': 'launch_application',
              'application_id': applicationId,
            },
          ),
        );
      case ListWindowsCommand():
        agentRequest = const ListWindowsAgentRequest();
        _publishDiscoveryRequested('list_windows');
      case GetActiveWindowCommand():
        agentRequest = const GetActiveWindowAgentRequest();
        _publishDiscoveryRequested('get_active_window');
    }

    final pcAgent = _findPcAgent();
    if (pcAgent == null) {
      return const Result.failure(
        Failure('PC Agent is not configured.', code: 'pc_agent_unavailable'),
      );
    }

    final result = await pcAgent.handle(agentRequest);
    return result.fold(
      (response) => Result.success(
        OrchestratorResponse(message: response.message, data: response.data),
      ),
      Result.failure,
    );
  }

  void _publishDiscoveryRequested(String operation) {
    events.publish(
      ApplicationEvent(
        type: 'window.discovery.requested',
        occurredAt: DateTime.now().toUtc(),
        data: {'operation': operation},
      ),
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
