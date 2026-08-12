import '../../core/result.dart';
import '../../core/security/permission.dart';
import '../../tools/tool.dart';
import '../../tools/windows/launch_application_tool.dart';
import '../agent.dart';

/// Routes structured PC commands to explicitly exposed tools.
final class PcAgent implements Agent {
  PcAgent({required this.launchApplicationTool, required this.authorizer});

  final LaunchApplicationTool launchApplicationTool;
  final PermissionAuthorizer authorizer;

  @override
  String get id => 'agent.pc';

  @override
  String get name => 'PC Agent';

  @override
  String get description => 'Routes approved structured PC operations.';

  @override
  List<Tool> get availableTools => [launchApplicationTool];

  @override
  Future<Result<AgentResponse>> handle(AgentRequest request) async {
    if (request is! LaunchApplicationAgentRequest) {
      return const Result.failure(
        Failure('Unsupported PC command.', code: 'unsupported_pc_command'),
      );
    }

    final result = await launchApplicationTool.execute({
      'application_id': request.applicationId,
    }, ToolExecutionContext(authorizer: authorizer));
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
