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

sealed class WindowControlCommand extends OrchestratorCommand {
  const WindowControlCommand({required this.windowId});

  final String windowId;
}

final class ActivateWindowCommand extends WindowControlCommand {
  const ActivateWindowCommand({required super.windowId});
}

final class MinimizeWindowCommand extends WindowControlCommand {
  const MinimizeWindowCommand({required super.windowId});
}

final class MaximizeWindowCommand extends WindowControlCommand {
  const MaximizeWindowCommand({required super.windowId});
}

final class RestoreWindowCommand extends WindowControlCommand {
  const RestoreWindowCommand({required super.windowId});
}

final class CloseWindowCommand extends WindowControlCommand {
  const CloseWindowCommand({required super.windowId});
}

final class InspectUiCommand extends OrchestratorCommand {
  const InspectUiCommand({
    required this.windowId,
    required this.maxDepth,
    required this.maxElements,
  });

  final String windowId;
  final int maxDepth;
  final int maxElements;
}

final class InvokeUiElementCommand extends OrchestratorCommand {
  const InvokeUiElementCommand({
    required this.windowId,
    required this.elementId,
  });

  final String windowId;
  final String elementId;
}

final class SetUiElementValueCommand extends OrchestratorCommand {
  const SetUiElementValueCommand({
    required this.windowId,
    required this.elementId,
    required this.value,
  });

  final String windowId;
  final String elementId;
  final String value;
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
      case ActivateWindowCommand(:final windowId):
        agentRequest = ActivateWindowAgentRequest(windowId: windowId);
        _publishWindowControlRequested('activate', windowId);
      case MinimizeWindowCommand(:final windowId):
        agentRequest = MinimizeWindowAgentRequest(windowId: windowId);
        _publishWindowControlRequested('minimize', windowId);
      case MaximizeWindowCommand(:final windowId):
        agentRequest = MaximizeWindowAgentRequest(windowId: windowId);
        _publishWindowControlRequested('maximize', windowId);
      case RestoreWindowCommand(:final windowId):
        agentRequest = RestoreWindowAgentRequest(windowId: windowId);
        _publishWindowControlRequested('restore', windowId);
      case CloseWindowCommand(:final windowId):
        agentRequest = CloseWindowAgentRequest(windowId: windowId);
        _publishWindowControlRequested('close', windowId);
      case InspectUiCommand(
        :final windowId,
        :final maxDepth,
        :final maxElements,
      ):
        agentRequest = InspectUiAgentRequest(
          windowId: windowId,
          maxDepth: maxDepth,
          maxElements: maxElements,
        );
        events.publish(
          ApplicationEvent(
            type: 'ui.inspection.requested',
            occurredAt: DateTime.now().toUtc(),
            data: {
              'window_id': windowId,
              'max_depth': maxDepth,
              'max_elements': maxElements,
            },
          ),
        );
      case InvokeUiElementCommand(:final windowId, :final elementId):
        agentRequest = InvokeUiElementAgentRequest(
          windowId: windowId,
          elementId: elementId,
        );
        events.publish(
          ApplicationEvent(
            type: 'ui.invoke.requested',
            occurredAt: DateTime.now().toUtc(),
            data: {'window_id': windowId, 'element_id': elementId},
          ),
        );
      case SetUiElementValueCommand(
        :final windowId,
        :final elementId,
        :final value,
      ):
        agentRequest = SetUiElementValueAgentRequest(
          windowId: windowId,
          elementId: elementId,
          value: value,
        );
        events.publish(
          ApplicationEvent(
            type: 'ui.value.requested',
            occurredAt: DateTime.now().toUtc(),
            data: {
              'operation': 'set_value',
              'window_id': windowId,
              'element_id': elementId,
            },
          ),
        );
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

  void _publishWindowControlRequested(String operation, String windowId) {
    events.publish(
      ApplicationEvent(
        type: 'window.control.requested',
        occurredAt: DateTime.now().toUtc(),
        data: {'operation': operation, 'window_id': windowId},
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
