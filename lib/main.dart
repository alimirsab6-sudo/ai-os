import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app/ai_os_app.dart';
import 'app/composition_root.dart';
import 'core/orchestrator/orchestrator.dart';
import 'browser/embedded/windows_webview2_browser_controller.dart';
import 'voice/speech_synthesizer.dart';
import 'voice/assistant/voice_assistant.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    fullScreen: false,
    title: 'CronyX AI OS',
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  await windowManager.waitUntilReadyToShow(
    windowOptions,
    () async {
      await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    },
  );

  final services = CompositionRoot.create();

  runApp(
    AiOsApp(
      orchestrator: services.get<Orchestrator>(),
      browserController:
          services.get<WindowsWebView2BrowserController>(),
      speechSynthesizer:
          services.get<SpeechSynthesizer>(),
      voiceAssistant:
          services.get<VoiceAssistant>(),
    ),
  );
}



