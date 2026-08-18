import 'dart:io';

import 'package:flutter/foundation.dart';

import '../agents/agent.dart';
import '../agents/browser_agent/browser_agent.dart';
import '../agents/pc_agent/pc_agent.dart';
import '../agents/voice_agent/voice_agent.dart';
import '../ai/model_provider/mock_model_provider.dart';
import '../ai/model_provider/model_provider.dart';
import '../browser/browser_session.dart';
import '../browser/browser_url_launcher.dart';
import '../browser/windows_browser_url_launcher.dart';
import '../browser/embedded/browser_controller.dart';
import '../browser/embedded/windows_webview2_browser_controller.dart';
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
import '../tools/browser/inspect_browser_context_tool.dart';
import '../tools/browser/embedded_browser_tool.dart';
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
import '../voice/audio/speech_audio_player.dart';
import '../voice/audio/windows_speech_audio_player.dart';
import '../voice/kokoro/kokoro_bridge.dart';
import '../voice/kokoro/kokoro_speech_synthesizer.dart';
import '../voice/kokoro/node_kokoro_bridge.dart';
import '../voice/speech_synthesizer.dart';
import '../voice/assistant/local_voice_assistant.dart';
import '../voice/assistant/voice_assistant.dart';
import '../voice/input/microphone_capture.dart';
import '../voice/input/record_microphone_capture.dart';
import '../voice/profile/local_owner_profile_repository.dart';
import '../voice/profile/owner_profile_repository.dart';
import '../voice/recognition/local_voice_runtime.dart';
import '../voice/recognition/sherpa_voice_runtime.dart';
import 'service_registry.dart';
import 'local_runtime_root.dart';

final class CompositionRoot {
  const CompositionRoot._();

  static ServiceRegistry create({AppConfiguration? configuration}) {
    final projectRoot = resolveLocalRuntimeRoot();
    final config = configuration ?? AppConfiguration.defaults();
    final events = EventBus();
    final authorizer = AllowListPermissionAuthorizer(config.permissions);
    final applicationRegistry = WindowsApplicationRegistry();
    final applicationAliases = Map<String, String>.unmodifiable({
      for (final application in applicationRegistry.listKnownApplications())
        for (final alias in application.aliases) alias: application.id,
    });
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
    final embeddedBrowserController = WindowsWebView2BrowserController();
    final embeddedBrowserTool = EmbeddedBrowserTool(
      controller: embeddedBrowserController,
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
    final inspectBrowserContextTool = InspectBrowserContextTool(
      windowDiscovery: windowDiscovery,
      uiAutomation: uiAutomation,
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
      inspectBrowserContextTool,
      embeddedBrowserTool,
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
        inspectBrowserContextTool: inspectBrowserContextTool,
        embeddedBrowserTool: embeddedBrowserTool,
      ),
    ];
    const provider = MockModelProvider(
      responseText: 'AI OS architecture foundation is ready.',
    );
    final kokoroProcessLauncher = FixedNodeKokoroProcessLauncher(
      projectRoot: projectRoot,
    );
    final kokoroBridge = NodeKokoroBridge(
      launcher: kokoroProcessLauncher,
      diagnostics: (message) => debugPrint('CRONYX_TTS $message'),
      allowedOutputDirectory:
          '$projectRoot${Platform.pathSeparator}runtime'
          '${Platform.pathSeparator}kokoro${Platform.pathSeparator}output'
          '${Platform.pathSeparator}bridge',
    );
    final speechAudioPlayer = WindowsSpeechAudioPlayer(
      diagnostics: (message) => debugPrint('CRONYX_TTS $message'),
    );
    final speechSynthesizer = KokoroSpeechSynthesizer(
      bridge: kokoroBridge,
      audioPlayer: speechAudioPlayer,
      events: events,
      diagnostics: (message) => debugPrint('CRONYX_TTS $message'),
    );
    final microphone = RecordMicrophoneCapture();
    final ownerProfiles = LocalOwnerProfileRepository();
    final voiceRuntime = SherpaVoiceRuntime(
      paths: VoiceRuntimePaths(projectRoot: projectRoot),
    );
    late final Orchestrator orchestrator;
    final voiceAssistant = LocalVoiceAssistant(
      microphone: microphone,
      runtime: voiceRuntime,
      profiles: ownerProfiles,
      speech: speechSynthesizer,
      events: events,
      commandHandler: (transcript) => orchestrator.handle(transcript),
      foundationReadiness: () => {
        'living_core': true,
        'orchestrator': true,
        'cronyx_browser': embeddedBrowserController.state.isInitialized,
        'pc_agent': agents.whereType<PcAgent>().isNotEmpty,
        'files_subsystem': false,
        'kokoro_runtime': File(
          '$projectRoot${Platform.pathSeparator}runtime'
          '${Platform.pathSeparator}kokoro${Platform.pathSeparator}model'
          '${Platform.pathSeparator}model_quantized.onnx',
        ).existsSync(),
        'af_bella': File(
          '$projectRoot${Platform.pathSeparator}runtime'
          '${Platform.pathSeparator}kokoro${Platform.pathSeparator}voices'
          '${Platform.pathSeparator}af_bella.bin',
        ).existsSync(),
      },
      diagnostics: (message) => debugPrint('CRONYX_VOICE $message'),
      lifecycleEvents: events.events,
    );
    agents.add(VoiceAgent(assistant: voiceAssistant));
    orchestrator = Orchestrator(
      modelProvider: provider,
      events: events,
      agents: agents,
      tools: tools,
      commandInterpreter: DeterministicCommandInterpreter(
        applicationAliases: applicationAliases,
        embeddedBrowserEnabled: true,
      ),
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
      ..register<BrowserController>(embeddedBrowserController)
      ..register<WindowsWebView2BrowserController>(embeddedBrowserController)
      ..register<EmbeddedBrowserTool>(embeddedBrowserTool)
      ..register<OpenUrlTool>(openUrlTool)
      ..register<InspectBrowserContextTool>(inspectBrowserContextTool)
      ..register<DiscoverChromeProfilesTool>(discoverChromeProfilesTool)
      ..register<LaunchChromeProfileTool>(launchChromeProfileTool)
      ..register<MemoryStore>(InMemoryStore())
      ..register<McpGateway>(const DisabledMcpGateway())
      ..register<Skill>(const PlaceholderSkill())
      ..register<ModelProvider>(provider)
      ..register<KokoroRuntimeProcessLauncher>(kokoroProcessLauncher)
      ..register<KokoroBridge>(kokoroBridge)
      ..register<SpeechAudioPlayer>(speechAudioPlayer)
      ..register<SpeechSynthesizer>(speechSynthesizer)
      ..register<MicrophoneCapture>(microphone)
      ..register<OwnerProfileRepository>(ownerProfiles)
      ..register<LocalVoiceRuntime>(voiceRuntime)
      ..register<VoiceAssistant>(voiceAssistant)
      ..register<PcAgent>(agents.whereType<PcAgent>().single)
      ..register<BrowserAgent>(agents.whereType<BrowserAgent>().single)
      ..register<VoiceAgent>(agents.whereType<VoiceAgent>().single)
      ..register<Orchestrator>(orchestrator);
  }
}
