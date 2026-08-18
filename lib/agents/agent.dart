import '../core/result.dart';
import '../tools/tool.dart';

sealed class AgentRequest {
  const AgentRequest();
}

final class LaunchApplicationAgentRequest extends AgentRequest {
  const LaunchApplicationAgentRequest({required this.applicationId});

  final String applicationId;
}

final class ListWindowsAgentRequest extends AgentRequest {
  const ListWindowsAgentRequest();
}

final class GetActiveWindowAgentRequest extends AgentRequest {
  const GetActiveWindowAgentRequest();
}

sealed class WindowControlAgentRequest extends AgentRequest {
  const WindowControlAgentRequest({required this.windowId});

  final String windowId;
}

final class ActivateWindowAgentRequest extends WindowControlAgentRequest {
  const ActivateWindowAgentRequest({required super.windowId});
}

final class MinimizeWindowAgentRequest extends WindowControlAgentRequest {
  const MinimizeWindowAgentRequest({required super.windowId});
}

final class MaximizeWindowAgentRequest extends WindowControlAgentRequest {
  const MaximizeWindowAgentRequest({required super.windowId});
}

final class RestoreWindowAgentRequest extends WindowControlAgentRequest {
  const RestoreWindowAgentRequest({required super.windowId});
}

final class CloseWindowAgentRequest extends WindowControlAgentRequest {
  const CloseWindowAgentRequest({required super.windowId});
}

final class InspectUiAgentRequest extends AgentRequest {
  const InspectUiAgentRequest({
    required this.windowId,
    required this.maxDepth,
    required this.maxElements,
  });

  final String windowId;
  final int maxDepth;
  final int maxElements;
}

final class InvokeUiElementAgentRequest extends AgentRequest {
  const InvokeUiElementAgentRequest({
    required this.windowId,
    required this.elementId,
  });

  final String windowId;
  final String elementId;
}

final class SetUiElementValueAgentRequest extends AgentRequest {
  const SetUiElementValueAgentRequest({
    required this.windowId,
    required this.elementId,
    required this.value,
  });

  final String windowId;
  final String elementId;
  final String value;
}

final class DiscoverChromeProfilesAgentRequest extends AgentRequest {
  const DiscoverChromeProfilesAgentRequest();
}

final class LaunchChromeProfileAgentRequest extends AgentRequest {
  const LaunchChromeProfileAgentRequest({required this.profileId});

  final String profileId;
}

final class OpenUrlAgentRequest extends AgentRequest {
  const OpenUrlAgentRequest({required this.url});

  final Uri url;
}

final class EmbeddedBrowserAgentRequest extends AgentRequest {
  const EmbeddedBrowserAgentRequest({required this.operation, this.url});

  final String operation;
  final Uri? url;
}

final class InspectBrowserContextAgentRequest extends AgentRequest {
  const InspectBrowserContextAgentRequest({
    this.windowId,
    this.maxDepth,
    this.maxElements,
  });

  final String? windowId;
  final int? maxDepth;
  final int? maxElements;
}

final class EnrollOwnerVoiceAgentRequest extends AgentRequest {
  const EnrollOwnerVoiceAgentRequest({required this.displayName});

  final String displayName;
}

final class ResetOwnerVoiceProfileAgentRequest extends AgentRequest {
  const ResetOwnerVoiceProfileAgentRequest();
}

final class DescribeVoiceSecurityActivityAgentRequest extends AgentRequest {
  const DescribeVoiceSecurityActivityAgentRequest();
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
