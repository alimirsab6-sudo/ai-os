import '../agents/agent.dart';
import '../agents/browser_agent/browser_agent.dart';
import '../agents/pc_agent/pc_agent.dart';
import '../ai/model_provider/mock_model_provider.dart';
import '../ai/model_provider/model_provider.dart';
import '../browser/browser_session.dart';
import '../browser/browser_url_launcher.dart';
import '../browser/windows_browser_url_launcher.dart';
import '../browser/chrome/chrome_installation_resolver.dart';
import '../browser/chrome/chrome_launcher.dart';
import '../browser/chrome/chrome_profile_registry.dart';
import '../browser/chrome/chrome_profile_tools.dart';
import '../browser/chrome/windows_chrome_installation_resolver.dart';
import '../browser/chrome/windows_chrome_launcher.dart';
import '../browser/chrome/windows_chrome_profile_registry.dart';
import '../core/configuration/app_configuration.dart';
import '../core/events/event_bus.dart';
import '../core/orchestrator/orchestrator.dart';
import '../core/security/permission.dart';
import '../mcp/mcp_gateway.dart';
import '../memory/memory_store.dart';
import '../skills/skill.dart';
import '../tools/browser/browser_tool.dart';
import '../tools/browser/open_url_tool.dart';
import '../tools/files/file_tool.dart';
import '../tools/terminal/terminal_tool.dart';
import '../tools/tool.dart';
import '../tools/windows/applications/application_launcher.dart';
import '../tools/windows/applications/application_registry.dart';
import '../tools/windows/applications/windows_application_registry.dart';
import '../tools/windows/applications/windows_process_launcher.dart';
import '../tools/windows/launch_application_tool.dart';
import '../tools/windows/discovery/window_discovery.dart';
import '../tools/windows/discovery/windows_window_discovery.dart';
import '../tools/windows/window_discovery_tools.dart';
import '../tools/windows/control/window_controller.dart';
import '../tools/windows/control/windows_window_controller.dart';
import '../tools/windows/window_control_tools.dart';
import '../tools/windows/inspect_ui_tool.dart';
import '../tools/windows/invoke_ui_element_tool.dart';
import '../tools/windows/set_ui_element_value_tool.dart';
import '../tools/windows/ui_automation/ui_automation.dart';
import '../tools/windows/ui_automation/windows_ui_automation.dart';
import 'service_registry.dart';

final class CompositionRoot {
  const CompositionRoot._();

  static ServiceRegistry create({AppConfiguration? configuration}) {
    final config = configuration ?? AppConfiguration.defaults();
    final events = EventBus();
    final authorizer = AllowListPermissionAuthorizer(config.permissions);
    final applicationRegistry = WindowsApplicationRegistry();
    final chromeInstallationResolver = WindowsChromeInstallationResolver(
      applications: applicationRegistry,
    );
    final chromeProfileRegistry = WindowsChromeProfileRegistry(
      installationResolver: chromeInstallationResolver,
    );
    final browserSession = BrowserSession();
    final browserUrlLauncher = WindowsBrowserUrlLauncher(
      applications: applicationRegistry,
    );
    final openUrlTool = OpenUrlTool(
      launcher: browserUrlLauncher,
      events: events,
    );
    final chromeLauncher = WindowsChromeLauncher(
      profiles: chromeProfileRegistry,
      installationResolver: chromeInstallationResolver,
    );
    final discoverChromeProfilesTool = DiscoverChromeProfilesTool(
      registry: chromeProfileRegistry,
      events: events,
    );
    final launchChromeProfileTool = LaunchChromeProfileTool(
      launcher: chromeLauncher,
      session: browserSession,
      events: events,
    );
    const applicationLauncher = WindowsProcessLauncher();
    final launchApplicationTool = LaunchApplicationTool(
      registry: applicationRegistry,
      launcher: applicationLauncher,
      events: events,
    );
    final windowDiscovery = WindowsWindowDiscovery(
      applicationRegistry: applicationRegistry,
    );
    final listWindowsTool = ListWindowsTool(
      discovery: windowDiscovery,
      events: events,
    );
    final getActiveWindowTool = GetActiveWindowTool(
      discovery: windowDiscovery,
      events: events,
    );
    final windowController = WindowsWindowController(
      discovery: windowDiscovery,
    );
    final activateWindowTool = ActivateWindowTool(
      controller: windowController,
      events: events,
    );
    final minimizeWindowTool = MinimizeWindowTool(
      controller: windowController,
      events: events,
    );
    final maximizeWindowTool = MaximizeWindowTool(
      controller: windowController,
      events: events,
    );
    final restoreWindowTool = RestoreWindowTool(
      controller: windowController,
      events: events,
    );
    final closeWindowTool = CloseWindowTool(
      controller: windowController,
      events: events,
    );
    final uiAutomation = WindowsUiAutomation(windowDiscovery: windowDiscovery);
    final inspectUiTool = InspectUiTool(
      uiAutomation: uiAutomation,
      windowDiscovery: windowDiscovery,
      events: events,
    );
    final invokeUiElementTool = InvokeUiElementTool(
      uiAutomation: uiAutomation,
      windowDiscovery: windowDiscovery,
      events: events,
    );
    final setUiElementValueTool = SetUiElementValueTool(
      uiAutomation: uiAutomation,
      windowDiscovery: windowDiscovery,
      events: events,
    );
    final tools = <Tool>[
      launchApplicationTool,
      listWindowsTool,
      getActiveWindowTool,
      activateWindowTool,
      minimizeWindowTool,
      maximizeWindowTool,
      restoreWindowTool,
      closeWindowTool,
      inspectUiTool,
      invokeUiElementTool,
      setUiElementValueTool,
      discoverChromeProfilesTool,
      launchChromeProfileTool,
      openUrlTool,
      const FileToolPlaceholder(),
      const BrowserToolPlaceholder(),
      const TerminalToolPlaceholder(),
    ];
    final agents = <Agent>[
      PcAgent(
        launchApplicationTool: launchApplicationTool,
        authorizer: authorizer,
        listWindowsTool: listWindowsTool,
        getActiveWindowTool: getActiveWindowTool,
        activateWindowTool: activateWindowTool,
        minimizeWindowTool: minimizeWindowTool,
        maximizeWindowTool: maximizeWindowTool,
        restoreWindowTool: restoreWindowTool,
        closeWindowTool: closeWindowTool,
        inspectUiTool: inspectUiTool,
        invokeUiElementTool: invokeUiElementTool,
        setUiElementValueTool: setUiElementValueTool,
      ),
      BrowserAgent(
        authorizer: authorizer,
        discoverChromeProfilesTool: discoverChromeProfilesTool,
        launchChromeProfileTool: launchChromeProfileTool,
        openUrlTool: openUrlTool,
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
      ..register<WindowDiscovery>(windowDiscovery)
      ..register<ListWindowsTool>(listWindowsTool)
      ..register<GetActiveWindowTool>(getActiveWindowTool)
      ..register<WindowController>(windowController)
      ..register<ActivateWindowTool>(activateWindowTool)
      ..register<MinimizeWindowTool>(minimizeWindowTool)
      ..register<MaximizeWindowTool>(maximizeWindowTool)
      ..register<RestoreWindowTool>(restoreWindowTool)
      ..register<CloseWindowTool>(closeWindowTool)
      ..register<UiAutomation>(uiAutomation)
      ..register<InspectUiTool>(inspectUiTool)
      ..register<InvokeUiElementTool>(invokeUiElementTool)
      ..register<SetUiElementValueTool>(setUiElementValueTool)
      ..register<ChromeInstallationResolver>(chromeInstallationResolver)
      ..register<ChromeProfileRegistry>(chromeProfileRegistry)
      ..register<ChromeLauncher>(chromeLauncher)
      ..register<BrowserSession>(browserSession)
      ..register<BrowserUrlLauncher>(browserUrlLauncher)
      ..register<OpenUrlTool>(openUrlTool)
      ..register<DiscoverChromeProfilesTool>(discoverChromeProfilesTool)
      ..register<LaunchChromeProfileTool>(launchChromeProfileTool)
      ..register<MemoryStore>(InMemoryStore())
      ..register<McpGateway>(const DisabledMcpGateway())
      ..register<Skill>(const PlaceholderSkill())
      ..register<ModelProvider>(provider)
      ..register<PcAgent>(agents.whereType<PcAgent>().single)
      ..register<BrowserAgent>(agents.whereType<BrowserAgent>().single)
      ..register<Orchestrator>(
        Orchestrator(
          modelProvider: provider,
          events: events,
          agents: agents,
          tools: tools,
          commandInterpreter: const DeterministicCommandInterpreter(),
        ),
      );
  }
}
