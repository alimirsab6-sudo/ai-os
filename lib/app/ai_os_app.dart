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

class AiOsApp extends StatefulWidget {
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
  State<AiOsApp> createState() => _AiOsAppState();
}

class _AiOsAppState extends State<AiOsApp> {
  final FaceCameraService _cameraService = FaceCameraService();
  final CronyxIdentityStore _identityStore = CronyxIdentityStore();

  bool _loading = true;
  bool _unlocked = false;
  bool _enrollmentMode = true;
  String? _error;
  late final Future<void> _speechWarmup;

  @override
  void initState() {
    super.initState();
    _speechWarmup = widget.speechSynthesizer.initialize().then((_) {});
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

  Future<void> _openCore(String name, {required bool returningUser}) async {
    if (!mounted) return;

    await _speechWarmup;
    if (!mounted) return;

    setState(() {
      _unlocked = true;
    });

    final greeting = returningUser
        ? 'Welcome back, $name. CronyX is ready.'
        : 'Welcome to CronyX, $name. Your identity has been enrolled.';

    unawaited(widget.speechSynthesizer.speak(greeting));
  }

  @override
  void dispose() {
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CronyX AI OS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF030507),
        fontFamily: 'Segoe UI',
        useMaterial3: true,
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF030507),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF3298FF)),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF030507),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'CronyX could not start.\n\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
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

    if (controller == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF030507),
        body: Center(
          child: Text(
            'Camera unavailable.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return FaceScanScreen(
      controller: controller,
      enrollmentMode: _enrollmentMode,
      onAccessGranted: (name, returningUser) {
        unawaited(_openCore(name, returningUser: returningUser));
      },
    );
  }
}
