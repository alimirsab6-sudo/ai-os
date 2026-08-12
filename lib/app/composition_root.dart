import '../agents/agent.dart';
import '../agents/pc_agent/pc_agent.dart';
import '../ai/model_provider/mock_model_provider.dart';
import '../ai/model_provider/model_provider.dart';
import '../core/configuration/app_configuration.dart';
import '../core/events/event_bus.dart';
import '../core/orchestrator/orchestrator.dart';
import '../core/security/permission.dart';
import '../mcp/mcp_gateway.dart';
import '../memory/memory_store.dart';
import '../skills/skill.dart';
import '../tools/browser/browser_tool.dart';
import '../tools/files/file_tool.dart';
import '../tools/terminal/terminal_tool.dart';
import '../tools/tool.dart';
import '../tools/windows/applications/application_launcher.dart';
import '../tools/windows/applications/application_registry.dart';
import '../tools/windows/applications/windows_application_registry.dart';
import '../tools/windows/applications/windows_process_launcher.dart';
import '../tools/windows/launch_application_tool.dart';
import 'service_registry.dart';

final class CompositionRoot {
  const CompositionRoot._();

  static ServiceRegistry create({AppConfiguration? configuration}) {
    final config = configuration ?? AppConfiguration.defaults();
    final events = EventBus();
    final authorizer = AllowListPermissionAuthorizer(config.permissions);
    final applicationRegistry = WindowsApplicationRegistry();
    const applicationLauncher = WindowsProcessLauncher();
    final launchApplicationTool = LaunchApplicationTool(
      registry: applicationRegistry,
      launcher: applicationLauncher,
      events: events,
    );
    final tools = <Tool>[
      launchApplicationTool,
      const FileToolPlaceholder(),
      const BrowserToolPlaceholder(),
      const TerminalToolPlaceholder(),
    ];
    final agents = <Agent>[
      PcAgent(
        launchApplicationTool: launchApplicationTool,
        authorizer: authorizer,
      ),
    ];
    const provider = MockModelProvider(
      responseText: 'AI OS architecture foundation is ready.',
    );
    return ServiceRegistry()
      ..register<AppConfiguration>(config)
      ..register<EventBus>(events)
      ..register<PermissionAuthorizer>(authorizer)
      ..register<ApplicationRegistry>(applicationRegistry)
      ..register<ApplicationLauncher>(applicationLauncher)
      ..register<LaunchApplicationTool>(launchApplicationTool)
      ..register<MemoryStore>(InMemoryStore())
      ..register<McpGateway>(const DisabledMcpGateway())
      ..register<Skill>(const PlaceholderSkill())
      ..register<ModelProvider>(provider)
      ..register<PcAgent>(agents.single as PcAgent)
      ..register<Orchestrator>(
        Orchestrator(
          modelProvider: provider,
          events: events,
          agents: agents,
          tools: tools,
        ),
      );
  }
}
