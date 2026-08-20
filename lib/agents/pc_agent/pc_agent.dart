import '../../core/result.dart';
import '../../core/security/permission.dart';
import '../../tools/tool.dart';
import '../../tools/windows/launch_application_tool.dart';
import '../../tools/windows/window_discovery_tools.dart';
import '../../tools/windows/window_control_tools.dart';
import '../../tools/windows/inspect_ui_tool.dart';
import '../../tools/windows/invoke_ui_element_tool.dart';
import '../../tools/windows/set_ui_element_value_tool.dart';
import '../agent.dart';

/// Routes structured PC commands to explicitly exposed tools.
final class PcAgent implements Agent {
  PcAgent({
    required this.launchApplicationTool,
    required this.authorizer,
    this.listWindowsTool,
    this.getActiveWindowTool,
    this.activateWindowTool,
    this.minimizeWindowTool,
    this.maximizeWindowTool,
    this.restoreWindowTool,
    this.closeWindowTool,
    this.inspectUiTool,
    this.invokeUiElementTool,
    this.setUiElementValueTool,
  });

  final LaunchApplicationTool launchApplicationTool;
  final PermissionAuthorizer authorizer;
  final ListWindowsTool? listWindowsTool;
  final GetActiveWindowTool? getActiveWindowTool;
  final ActivateWindowTool? activateWindowTool;
  final MinimizeWindowTool? minimizeWindowTool;
  final MaximizeWindowTool? maximizeWindowTool;
  final RestoreWindowTool? restoreWindowTool;
  final CloseWindowTool? closeWindowTool;
  final InspectUiTool? inspectUiTool;
  final InvokeUiElementTool? invokeUiElementTool;
  final SetUiElementValueTool? setUiElementValueTool;

  @override
  String get id => 'agent.pc';

  @override
  String get name => 'PC Agent';

  @override
  String get description => 'Routes approved structured PC operations.';

  @override
  List<Tool> get availableTools => [
    launchApplicationTool,
    ?listWindowsTool,
    ?getActiveWindowTool,
    ?activateWindowTool,
    ?minimizeWindowTool,
    ?maximizeWindowTool,
    ?restoreWindowTool,
    ?closeWindowTool,
    ?inspectUiTool,
    ?invokeUiElementTool,
    ?setUiElementValueTool,
  ];

  @override
  Future<Result<AgentResponse>> handle(AgentRequest request) async {
    final Tool? tool;
    final Map<String, Object?> input;
    if (request is LaunchApplicationAgentRequest) {
      tool = launchApplicationTool;
      input = {'application_id': request.applicationId};
    } else if (request is ListWindowsAgentRequest) {
      tool = listWindowsTool;
      input = const {};
    } else if (request is GetActiveWindowAgentRequest) {
      tool = getActiveWindowTool;
      input = const {};
    } else if (request is ActivateWindowAgentRequest) {
      tool = activateWindowTool;
      input = {'window_id': request.windowId};
    } else if (request is MinimizeWindowAgentRequest) {
      tool = minimizeWindowTool;
      input = {'window_id': request.windowId};
    } else if (request is MaximizeWindowAgentRequest) {
      tool = maximizeWindowTool;
      input = {'window_id': request.windowId};
    } else if (request is RestoreWindowAgentRequest) {
      tool = restoreWindowTool;
      input = {'window_id': request.windowId};
    } else if (request is CloseWindowAgentRequest) {
      tool = closeWindowTool;
      input = {'window_id': request.windowId};
    } else if (request is InspectUiAgentRequest) {
      tool = inspectUiTool;
      input = {
        'window_id': request.windowId,
        'max_depth': request.maxDepth,
        'max_elements': request.maxElements,
      };
    } else if (request is InvokeUiElementAgentRequest) {
      tool = invokeUiElementTool;
      input = {'window_id': request.windowId, 'element_id': request.elementId};
    } else if (request is SetUiElementValueAgentRequest) {
      tool = setUiElementValueTool;
      input = {
        'window_id': request.windowId,
        'element_id': request.elementId,
        'value': request.value,
      };
    } else {
      tool = null;
      input = const {};
    }
    if (tool == null) {
      return const Result.failure(
        Failure('Unsupported PC command.', code: 'unsupported_pc_command'),
      );
    }

    final result = await tool.execute(
      input,
      ToolExecutionContext(authorizer: authorizer),
    );
    return result.fold(
      (output) => Result.success(
        AgentResponse(
          message: output.summary ?? 'Application launched.',
          data: output.data,
        ),
      ),
      Result.failure,
    );
  }
}

