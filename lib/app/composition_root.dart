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
import '../tools/windows/windows_tool.dart';
import 'service_registry.dart';

final class CompositionRoot {
  const CompositionRoot._();

  static ServiceRegistry create({AppConfiguration? configuration}) {
    final config = configuration ?? AppConfiguration.defaults();
    final events = EventBus();
    final tools = <Tool>[
      const WindowsToolPlaceholder(),
      const FileToolPlaceholder(),
      const BrowserToolPlaceholder(),
      const TerminalToolPlaceholder(),
    ];
    final agents = <Agent>[PcAgent(tools: tools)];
    const provider = MockModelProvider(
      responseText: 'AI OS architecture foundation is ready.',
    );
    return ServiceRegistry()
      ..register<AppConfiguration>(config)
      ..register<EventBus>(events)
      ..register<PermissionAuthorizer>(
        AllowListPermissionAuthorizer(config.permissions),
      )
      ..register<MemoryStore>(InMemoryStore())
      ..register<McpGateway>(const DisabledMcpGateway())
      ..register<Skill>(const PlaceholderSkill())
      ..register<ModelProvider>(provider)
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
