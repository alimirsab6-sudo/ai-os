import 'package:flutter/material.dart';

import '../core/orchestrator/orchestrator.dart';
import '../browser/embedded/windows_webview2_browser_controller.dart';
import '../ui/shell/cronyx_os_shell.dart';
import '../voice/speech_synthesizer.dart';
import '../voice/assistant/voice_assistant.dart';

class AiOsApp extends StatelessWidget {
  const AiOsApp({
    required this.orchestrator,
    required this.browserController,
    required this.speechSynthesizer,
    this.voiceAssistant,
    super.key,
  });

  final Orchestrator orchestrator;
  final WindowsWebView2BrowserController browserController;
  final SpeechSynthesizer speechSynthesizer;
  final VoiceAssistant? voiceAssistant;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CronyX AI OS',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF030507),
      fontFamily: 'Segoe UI',
      useMaterial3: true,
    ),
    home: CronyxOsShell(
      orchestrator: orchestrator,
      browserController: browserController,
      speechSynthesizer: speechSynthesizer,
      voiceAssistant: voiceAssistant,
      browserSurfaceBuilder: (context, controller) =>
          WindowsWebView2Surface(controller: browserController),
    ),
  );
}
