import 'dart:async';

import 'package:flutter/material.dart';

import '../browser/embedded/windows_webview2_browser_controller.dart';
import '../core/orchestrator/orchestrator.dart';
import '../face/face_camera_service.dart';
import '../face/face_identity_profile.dart';
import '../ui/face/face_scan_screen.dart';
import '../ui/shell/cronyx_os_shell.dart';
import '../voice/assistant/voice_assistant.dart';
import '../voice/speech_synthesizer.dart';

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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CronyX AI OS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF02070C),
        fontFamily: 'Segoe UI',
        useMaterial3: true,
      ),
      home: _StartupGate(
        orchestrator: orchestrator,
        browserController: browserController,
        speechSynthesizer: speechSynthesizer,
        voiceAssistant: voiceAssistant,
      ),
    );
  }
}

class _StartupGate extends StatefulWidget {
  const _StartupGate({
    required this.orchestrator,
    required this.browserController,
    required this.speechSynthesizer,
    required this.voiceAssistant,
  });

  final Orchestrator orchestrator;
  final WindowsWebView2BrowserController browserController;
  final SpeechSynthesizer speechSynthesizer;
  final VoiceAssistant? voiceAssistant;

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  final FaceCameraService _cameraService = FaceCameraService();

  final CronyxIdentityStore _identityStore = CronyxIdentityStore();

  bool _loading = true;
  bool _unlocked = false;
  bool _enrollmentMode = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepareStartup();
  }

  Future<void> _prepareStartup() async {
    try {
      final profile = await _identityStore.load();

      await _cameraService.initialize();

      if (!mounted) return;

      setState(() {
        _enrollmentMode = profile == null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _openCore(String name, {required bool returningUser}) {
    if (!mounted) return;

    setState(() {
      _unlocked = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        widget.speechSynthesizer.speak('Welcome back, $name. CronyX is ready.'),
      );
    });
  }

  @override
  void dispose() {
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF02070C),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF02070C),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Color(0xFFFF5E5E),
                size: 60,
              ),
              const SizedBox(height: 18),
              const Text(
                'CRONYX STARTUP ERROR',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8C9AA7)),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });

                  _prepareStartup();
                },
                child: const Text('RETRY'),
              ),
            ],
          ),
        ),
      );
    }

    if (_unlocked) {
      return CronyxOsShell(
        orchestrator: widget.orchestrator,
        browserController: widget.browserController,
        speechSynthesizer: widget.speechSynthesizer,
        voiceAssistant: widget.voiceAssistant,
        browserSurfaceBuilder: (context, controller) =>
            WindowsWebView2Surface(controller: widget.browserController),
      );
    }

    final controller = _cameraService.controller;

    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF02070C),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return FaceScanScreen(
      controller: controller,
      enrollmentMode: _enrollmentMode,
      onAccessGranted: (name) => _openCore(name, returningUser: !_enrollmentMode),
    );
  }
}



