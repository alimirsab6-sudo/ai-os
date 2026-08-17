import '../../browser/chrome/chrome_profile_tools.dart';
import '../../core/result.dart';
import '../../core/security/permission.dart';
import '../../tools/tool.dart';
import '../../tools/browser/open_url_tool.dart';
import '../agent.dart';

final class BrowserAgent implements Agent {
  const BrowserAgent({
    required this.authorizer,
    required this.discoverChromeProfilesTool,
    required this.launchChromeProfileTool,
    this.openUrlTool,
  });

  final PermissionAuthorizer authorizer;
  final DiscoverChromeProfilesTool discoverChromeProfilesTool;
  final LaunchChromeProfileTool launchChromeProfileTool;
  final OpenUrlTool? openUrlTool;

  @override
  String get id => 'agent.browser';
  @override
  String get name => 'Browser Agent';
  @override
  String get description => 'Routes deterministic browser profile operations.';
  @override
  List<Tool> get availableTools => [
    discoverChromeProfilesTool,
    launchChromeProfileTool,
    ?openUrlTool,
  ];

  @override
  Future<Result<AgentResponse>> handle(AgentRequest request) async {
    final Tool tool;
    final Map<String, Object?> input;
    switch (request) {
      case DiscoverChromeProfilesAgentRequest():
        tool = discoverChromeProfilesTool;
        input = const {};
      case LaunchChromeProfileAgentRequest(:final profileId):
        tool = launchChromeProfileTool;
        input = {'profile_id': profileId};
      case OpenUrlAgentRequest(:final url) when openUrlTool != null:
        tool = openUrlTool!;
        input = {'url': url.toString()};
      default:
        return const Result.failure(
          Failure(
            'Unsupported browser command.',
            code: 'unsupported_browser_command',
          ),
        );
    }
    final result = await tool.execute(
      input,
      ToolExecutionContext(authorizer: authorizer),
    );
    return result.fold(
      (output) => Result.success(
        AgentResponse(
          message: output.summary ?? 'Browser operation completed.',
          data: output.data,
        ),
      ),
      Result.failure,
    );
  }
}
