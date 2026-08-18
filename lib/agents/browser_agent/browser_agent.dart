import '../../browser/chrome/chrome_profile_tools.dart';
import '../../core/result.dart';
import '../../core/security/permission.dart';
import '../../tools/tool.dart';
import '../../tools/browser/open_url_tool.dart';
import '../../tools/browser/inspect_browser_context_tool.dart';
import '../../tools/browser/embedded_browser_tool.dart';
import '../agent.dart';

final class BrowserAgent implements Agent {
  const BrowserAgent({
    required this.authorizer,
    required this.discoverChromeProfilesTool,
    required this.launchChromeProfileTool,
    this.openUrlTool,
    this.inspectBrowserContextTool,
    this.embeddedBrowserTool,
  });

  final PermissionAuthorizer authorizer;
  final DiscoverChromeProfilesTool discoverChromeProfilesTool;
  final LaunchChromeProfileTool launchChromeProfileTool;
  final OpenUrlTool? openUrlTool;
  final InspectBrowserContextTool? inspectBrowserContextTool;
  final EmbeddedBrowserTool? embeddedBrowserTool;

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
    ?inspectBrowserContextTool,
    ?embeddedBrowserTool,
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
      case OpenUrlAgentRequest(:final url) when embeddedBrowserTool != null:
        tool = embeddedBrowserTool!;
        input = {
          'operation': EmbeddedBrowserOperation.navigate.id,
          'url': url.toString(),
        };
      case OpenUrlAgentRequest(:final url) when openUrlTool != null:
        tool = openUrlTool!;
        input = {'url': url.toString()};
      case EmbeddedBrowserAgentRequest(:final operation, :final url)
          when embeddedBrowserTool != null:
        tool = embeddedBrowserTool!;
        input = {'operation': operation, 'url': url?.toString()};
      case InspectBrowserContextAgentRequest(
            :final windowId,
            :final maxDepth,
            :final maxElements,
          )
          when inspectBrowserContextTool != null:
        tool = inspectBrowserContextTool!;
        input = {
          'window_id': windowId,
          'max_depth': maxDepth,
          'max_elements': maxElements,
        };
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
