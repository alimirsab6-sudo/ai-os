import '../../core/result.dart';
import '../../core/security/permission.dart';
import '../../tools/tool.dart';
import '../../tools/windows/launch_application_tool.dart';
import '../../tools/windows/window_discovery_tools.dart';
import '../agent.dart';

/// Routes structured PC commands to explicitly exposed tools.
final class PcAgent implements Agent {
  PcAgent({
    required this.launchApplicationTool,
    required this.authorizer,
    this.listWindowsTool,
    this.getActiveWindowTool,
  });

  final LaunchApplicationTool launchApplicationTool;
  final PermissionAuthorizer authorizer;
  final ListWindowsTool? listWindowsTool;
  final GetActiveWindowTool? getActiveWindowTool;

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
