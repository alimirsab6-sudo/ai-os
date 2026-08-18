import '../../agents/agent.dart';
import '../../agents/browser_agent/browser_agent.dart';
import '../../agents/pc_agent/pc_agent.dart';
import '../../agents/voice_agent/voice_agent.dart';
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

final class DiscoverChromeProfilesCommand extends OrchestratorCommand {
  const DiscoverChromeProfilesCommand();
}

final class LaunchChromeProfileCommand extends OrchestratorCommand {
  const LaunchChromeProfileCommand({required this.profileId});

  final String profileId;
}

final class OpenUrlCommand extends OrchestratorCommand {
  const OpenUrlCommand({required this.url});

  final Uri url;
}

final class InitializeBrowserCommand extends OrchestratorCommand {
  const InitializeBrowserCommand();
}

sealed class BrowserNavigationCommand extends OrchestratorCommand {
  const BrowserNavigationCommand();
}

final class BrowserBackCommand extends BrowserNavigationCommand {
  const BrowserBackCommand();
}

final class BrowserForwardCommand extends BrowserNavigationCommand {
  const BrowserForwardCommand();
}

final class BrowserReloadCommand extends BrowserNavigationCommand {
  const BrowserReloadCommand();
}

final class DisposeBrowserCommand extends OrchestratorCommand {
  const DisposeBrowserCommand();
}

final class InspectBrowserContextCommand extends OrchestratorCommand {
  const InspectBrowserContextCommand({
    this.windowId,
    this.maxDepth,
    this.maxElements,
  });

  final String? windowId;
  final int? maxDepth;
  final int? maxElements;
}

final class EnrollOwnerVoiceCommand extends OrchestratorCommand {
  const EnrollOwnerVoiceCommand({required this.displayName});

  final String displayName;
}

final class ResetOwnerVoiceProfileCommand extends OrchestratorCommand {
  const ResetOwnerVoiceProfileCommand();
}

final class DescribeVoiceSecurityActivityCommand extends OrchestratorCommand {
  const DescribeVoiceSecurityActivityCommand();
}

abstract interface class CommandInterpreter {
  Result<OrchestratorCommand> interpret(String request);
}

/// Recognizes only the explicit, controlled actions exposed by this phase.
/// Unrecognized text never becomes a process or shell command.
final class DeterministicCommandInterpreter implements CommandInterpreter {
  const DeterministicCommandInterpreter({
    this.applicationAliases = _defaultApplicationAliases,
    this.embeddedBrowserEnabled = false,
  });

  static const Map<String, String> _defaultApplicationAliases = {
    'chrome': 'chrome',
    'google chrome': 'chrome',
    'browser': 'chrome',
    'edge': 'edge',
    'microsoft edge': 'edge',
    'notepad': 'notepad',
    'calculator': 'calculator',
    'calc': 'calculator',
    'file explorer': 'file_explorer',
    'explorer': 'file_explorer',
    'my pc': 'file_explorer',
    'settings': 'settings',
    'windows settings': 'settings',
    'task manager': 'task_manager',
    'tasks': 'task_manager',
  };

  static const Map<String, String> _directActionAliases = {
    'browse files': 'file_explorer',
    'show my files': 'file_explorer',
    'view tasks': 'task_manager',
  };

  static const Map<String, String> _websiteAliases = {
    'google': 'https://google.com',
    'youtube': 'https://youtube.com',
  };

  final Map<String, String> applicationAliases;
  final bool embeddedBrowserEnabled;

  @override
  Result<OrchestratorCommand> interpret(String request) {
    var normalized = request.trim().replaceAll(RegExp(r'\s+'), ' ');
    normalized = normalized.replaceAll(RegExp(r'[.!?]+$'), '').trim();
    normalized = normalized.replaceFirst(
      RegExp(
        r'^(?:(?:could|can) you(?: please)?|please)\s+',
        caseSensitive: false,
      ),
      '',
    );

    if (const {
      'inspect browser',
      'inspect my browser',
      "what's open in my browser",
    }.contains(normalized.toLowerCase())) {
      return const Result.success(InspectBrowserContextCommand());
    }

    final lower = normalized.toLowerCase();
    final enrollment = RegExp(
      r'^enroll (?:my )?voice as (.+)$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (enrollment != null) {
      final displayName = enrollment.group(1)!.trim();
      if (displayName.isEmpty || displayName.length > 40) {
        return const Result.failure(
          Failure('Enter a valid owner name.', code: 'invalid_owner_name'),
        );
      }
      return Result.success(EnrollOwnerVoiceCommand(displayName: displayName));
    }
    if (lower == 'reset voice profile' || lower == 'reset owner voice') {
      return const Result.success(ResetOwnerVoiceProfileCommand());
    }
    if (lower == 'what happened' || lower == 'what did they do') {
      return const Result.success(DescribeVoiceSecurityActivityCommand());
    }
    final browserInitialization = RegExp(
      r'^(?:open|show|launch|on)(?: (?:the|a|my))? brows?er$',
    );
    if (embeddedBrowserEnabled && browserInitialization.hasMatch(lower)) {
      return const Result.success(InitializeBrowserCommand());
    }
    if (embeddedBrowserEnabled && lower == 'go back') {
      return const Result.success(BrowserBackCommand());
    }
    if (embeddedBrowserEnabled && lower == 'go forward') {
      return const Result.success(BrowserForwardCommand());
    }
    if (embeddedBrowserEnabled &&
        (lower == 'reload' || lower == 'reload page')) {
      return const Result.success(BrowserReloadCommand());
    }

    final directApplicationId = _directActionAliases[normalized.toLowerCase()];
    if (directApplicationId != null) {
      return Result.success(
        LaunchApplicationCommand(applicationId: directApplicationId),
      );
    }

    final actionMatch = RegExp(
      r'^(open|launch|start|browse|go to|navigate to)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (actionMatch == null) return _unsupportedCommand();

    final action = actionMatch.group(1)!.toLowerCase();
    final target = actionMatch.group(2)!.trim();
    final website = embeddedBrowserEnabled
        ? _websiteAliases[target.toLowerCase()]
        : null;
    if (website != null) {
      return Result.success(OpenUrlCommand(url: Uri.parse(website)));
    }
    final applicationId =
        action == 'open' || action == 'launch' || action == 'start'
        ? applicationAliases[target.toLowerCase()]
        : null;
    if (applicationId != null) {
      return Result.success(
        LaunchApplicationCommand(applicationId: applicationId),
      );
    }

    final url = Uri.tryParse(target);
    if (url != null && url.hasScheme) {
      if ((url.scheme == 'http' || url.scheme == 'https') &&
          url.host.isNotEmpty &&
          url.userInfo.isEmpty) {
        return Result.success(OpenUrlCommand(url: url));
      }
      return const Result.failure(
        Failure(
          'That web address is not a valid HTTP or HTTPS URL.',
          code: 'invalid_url',
        ),
      );
    }
    return _unsupportedCommand();
  }

  Result<OrchestratorCommand> _unsupportedCommand() => const Result.failure(
    Failure('That command is not supported yet.', code: 'unsupported_command'),
  );
}

/// Coordinates requests while keeping providers, agents, and tools replaceable.
final class Orchestrator {
  Orchestrator({
    required this.modelProvider,
    required this.events,
    List<Agent> agents = const [],
    List<Tool> tools = const [],
    this.commandInterpreter,
  }) : agents = List.unmodifiable(agents),
       tools = List.unmodifiable(tools);

  final ModelProvider modelProvider;
  final EventPublisher events;
  final List<Agent> agents;
  final List<Tool> tools;
  final CommandInterpreter? commandInterpreter;

  Stream<AppEvent>? get eventStream =>
      events is EventBus ? (events as EventBus).events : null;

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
    final interpreter = commandInterpreter;
    if (interpreter != null) {
      final interpreted = interpreter.interpret(userRequest);
      if (interpreted case Failed<OrchestratorCommand>(:final failure)) {
        events.publish(
          ApplicationEvent(
            type: 'orchestrator.request.rejected',
            occurredAt: DateTime.now().toUtc(),
            data: {'failure_code': failure.code},
          ),
        );
        return Result.failure(failure);
      }
      final command = (interpreted as Success<OrchestratorCommand>).value;
      events.publish(
        ApplicationEvent(
          type: 'orchestrator.command.selected',
          occurredAt: DateTime.now().toUtc(),
          data: _commandSelectionData(command),
        ),
      );
      return executeCommand(command);
    }
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
      case DiscoverChromeProfilesCommand():
        agentRequest = const DiscoverChromeProfilesAgentRequest();
        events.publish(
          ApplicationEvent(
            type: 'chrome.profile.discovery.requested',
            occurredAt: DateTime.now().toUtc(),
          ),
        );
      case LaunchChromeProfileCommand(:final profileId):
        agentRequest = LaunchChromeProfileAgentRequest(profileId: profileId);
        events.publish(
          ApplicationEvent(
            type: 'chrome.profile.launch.requested',
            occurredAt: DateTime.now().toUtc(),
            data: {'profile_id': profileId},
          ),
        );
      case OpenUrlCommand(:final url):
        agentRequest = OpenUrlAgentRequest(url: url);
        events.publish(
          ApplicationEvent(
            type: 'browser.url.requested',
            occurredAt: DateTime.now().toUtc(),
            data: {'host': url.host},
          ),
        );
      case InitializeBrowserCommand():
        agentRequest = const EmbeddedBrowserAgentRequest(
          operation: 'initialize',
        );
        _publishBrowserCommandRequested('initialize');
      case BrowserBackCommand():
        agentRequest = const EmbeddedBrowserAgentRequest(operation: 'back');
        _publishBrowserCommandRequested('back');
      case BrowserForwardCommand():
        agentRequest = const EmbeddedBrowserAgentRequest(operation: 'forward');
        _publishBrowserCommandRequested('forward');
      case BrowserReloadCommand():
        agentRequest = const EmbeddedBrowserAgentRequest(operation: 'reload');
        _publishBrowserCommandRequested('reload');
      case DisposeBrowserCommand():
        agentRequest = const EmbeddedBrowserAgentRequest(operation: 'dispose');
        _publishBrowserCommandRequested('dispose');
      case InspectBrowserContextCommand(
        :final windowId,
        :final maxDepth,
        :final maxElements,
      ):
        agentRequest = InspectBrowserContextAgentRequest(
          windowId: windowId,
          maxDepth: maxDepth,
          maxElements: maxElements,
        );
        events.publish(
          ApplicationEvent(
            type: 'browser.context.inspection.requested',
            occurredAt: DateTime.now().toUtc(),
            data: {
              'window_id': windowId,
              'max_depth': maxDepth,
              'max_elements': maxElements,
            },
          ),
        );
      case EnrollOwnerVoiceCommand(:final displayName):
        agentRequest = EnrollOwnerVoiceAgentRequest(displayName: displayName);
        events.publish(
          ApplicationEvent(
            type: 'voice.enrollment.requested',
            occurredAt: DateTime.now().toUtc(),
          ),
        );
      case ResetOwnerVoiceProfileCommand():
        agentRequest = const ResetOwnerVoiceProfileAgentRequest();
        events.publish(
          ApplicationEvent(
            type: 'voice.profile.reset.requested',
            occurredAt: DateTime.now().toUtc(),
          ),
        );
      case DescribeVoiceSecurityActivityCommand():
        agentRequest = const DescribeVoiceSecurityActivityAgentRequest();
        events.publish(
          ApplicationEvent(
            type: 'voice.security.activity.requested',
            occurredAt: DateTime.now().toUtc(),
          ),
        );
    }

    final Agent? targetAgent = switch (agentRequest) {
      DiscoverChromeProfilesAgentRequest() ||
      LaunchChromeProfileAgentRequest() ||
      OpenUrlAgentRequest() => _findBrowserAgent(),
      EmbeddedBrowserAgentRequest() => _findBrowserAgent(),
      InspectBrowserContextAgentRequest() => _findBrowserAgent(),
      EnrollOwnerVoiceAgentRequest() ||
      ResetOwnerVoiceProfileAgentRequest() ||
      DescribeVoiceSecurityActivityAgentRequest() => _findVoiceAgent(),
      _ => _findPcAgent(),
    };
    if (targetAgent == null) {
      return const Result.failure(
        Failure('Required agent is not configured.', code: 'agent_unavailable'),
      );
    }

    final result = await targetAgent.handle(agentRequest);
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

  void _publishBrowserCommandRequested(String operation) {
    events.publish(
      ApplicationEvent(
        type: 'browser.command.requested',
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

  BrowserAgent? _findBrowserAgent() {
    for (final agent in agents) {
      if (agent is BrowserAgent) return agent;
    }
    return null;
  }

  VoiceAgent? _findVoiceAgent() {
    for (final agent in agents) {
      if (agent is VoiceAgent) return agent;
    }
    return null;
  }

  Map<String, Object?> _commandSelectionData(OrchestratorCommand command) =>
      switch (command) {
        LaunchApplicationCommand(:final applicationId) => {
          'action': 'launch_application',
          'agent': 'PC Agent',
          'application_id': applicationId,
        },
        OpenUrlCommand(:final url) => {
          'action': 'open_url',
          'agent': 'Browser Agent',
          'host': url.host,
        },
        InitializeBrowserCommand() => {
          'action': 'initialize_browser',
          'agent': 'Browser Agent',
        },
        BrowserBackCommand() => {
          'action': 'browser_back',
          'agent': 'Browser Agent',
        },
        BrowserForwardCommand() => {
          'action': 'browser_forward',
          'agent': 'Browser Agent',
        },
        BrowserReloadCommand() => {
          'action': 'browser_reload',
          'agent': 'Browser Agent',
        },
        DisposeBrowserCommand() => {
          'action': 'dispose_browser',
          'agent': 'Browser Agent',
        },
        InspectBrowserContextCommand() => {
          'action': 'inspect_browser_context',
          'agent': 'Browser Agent',
        },
        EnrollOwnerVoiceCommand() => {
          'action': 'enroll_owner_voice',
          'agent': 'Voice Agent',
        },
        ResetOwnerVoiceProfileCommand() => {
          'action': 'reset_owner_voice',
          'agent': 'Voice Agent',
        },
        DescribeVoiceSecurityActivityCommand() => {
          'action': 'describe_voice_security_activity',
          'agent': 'Voice Agent',
        },
        _ => {'action': command.runtimeType.toString()},
      };

  ModelToolDefinition _toModelTool(Tool tool) => ModelToolDefinition(
    id: tool.id,
    name: tool.name,
    description: tool.description,
    inputFields: tool.inputSchema.fields.map(
      (name, field) => MapEntry(name, field.type.name),
    ),
  );
}
