import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/events/app_event.dart';
import '../../core/orchestrator/orchestrator.dart';
import '../../core/result.dart';
import '../../browser/embedded/browser_controller.dart';
import '../browser/cronyx_browser_workspace.dart';
import '../world/ai_core/ai_core.dart';
import '../world/ai_core/ai_core_controller.dart';
import '../world/ai_core/ai_core_state.dart';
import '../../voice/speech_synthesizer.dart';
import '../../voice/assistant/voice_assistant.dart';

class CronyxOsShell extends StatefulWidget {
  const CronyxOsShell({
    required this.orchestrator,
    this.coreController,
    this.onCoreStateChanged,
    this.browserController,
    this.browserSurfaceBuilder,
    this.speechSynthesizer,
    this.voiceAssistant,
    super.key,
  });

  final Orchestrator orchestrator;
  final AiCoreController? coreController;
  final ValueChanged<AiCoreState>? onCoreStateChanged;
  final BrowserController? browserController;
  final BrowserSurfaceBuilder? browserSurfaceBuilder;
  final SpeechSynthesizer? speechSynthesizer;
  final VoiceAssistant? voiceAssistant;

  @override
  State<CronyxOsShell> createState() => _CronyxOsShellState();
}

class _CronyxOsShellState extends State<CronyxOsShell> {
  late final AiCoreController _coreController;
  late final bool _ownsCoreController;
  StreamSubscription<AppEvent>? _eventSubscription;
  final TextEditingController _commandController = TextEditingController();
  final FocusNode _commandFocus = FocusNode();
  final List<_ActivityItem> _activity = <_ActivityItem>[
    _ActivityItem('Core initialized', 'System', 'Now'),
  ];

  String _actionTitle = 'Waiting for your request';
  String _actionAgent = 'Assistant Core';
  double _progress = 0;
  List<_ActionStep> _steps = const [
    _ActionStep('Waiting for input', _ActionStepStatus.pending),
  ];
  bool _busy = false;
  Future<void>? _browserSessionTransition;
  Timer? _idleTimer;
  String _activeTarget = 'requested action';
  _Workspace _workspace = _Workspace.core;

  @override
  void initState() {
    super.initState();
    _ownsCoreController = widget.coreController == null;
    _coreController = widget.coreController ?? AiCoreController();
    _eventSubscription = widget.orchestrator.eventStream?.listen(
      _handleBackendEvent,
    );
    final speechSynthesizer = widget.speechSynthesizer;
    if (speechSynthesizer != null) {
      unawaited(speechSynthesizer.initialize());
    }
    final voiceAssistant = widget.voiceAssistant;
    if (voiceAssistant != null) {
      unawaited(
        voiceAssistant.initialize().then((result) async {
          if (result is Success<void>) {
            await voiceAssistant.startWakeMonitoring();
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _eventSubscription?.cancel();
    _commandController.dispose();
    _commandFocus.dispose();
    final speechSynthesizer = widget.speechSynthesizer;
    if (speechSynthesizer != null) {
      unawaited(speechSynthesizer.dispose());
    }
    final voiceAssistant = widget.voiceAssistant;
    if (voiceAssistant != null) unawaited(voiceAssistant.dispose());
    if (widget.browserController?.state.isInitialized ?? false) {
      unawaited(
        widget.orchestrator.executeCommand(const DisposeBrowserCommand()),
      );
    }
    if (_ownsCoreController) _coreController.dispose();
    super.dispose();
  }

  Future<void> _submitCommand([String? value]) async {
    await _browserSessionTransition;
    if (_busy) return;
    final command = (value ?? _commandController.text).trim();
    if (command.isEmpty) {
      _commandFocus.requestFocus();
      return;
    }

    _commandController.clear();
    _idleTimer?.cancel();
    setState(() {
      _busy = true;
      _activeTarget = command;
      _activity.insert(0, _ActivityItem(command, 'You', 'Now'));
    });

    _setState(
      AiCoreState.thinking,
      title: 'Understanding your request',
      agent: 'AI Orchestrator',
      progress: .18,
      steps: const [
        _ActionStep('Understand request', _ActionStepStatus.active),
        _ActionStep('Select agent', _ActionStepStatus.pending),
        _ActionStep('Execute action', _ActionStepStatus.pending),
      ],
    );

    try {
      final result = await widget.orchestrator.handle(command);
      if (!mounted) return;

      await result.fold<Future<void>>(
        (response) async {
          if (!mounted) return;
          if (response.data['awaiting_page_load'] != true) {
            _finishSuccess(
              title: response.message.isEmpty
                  ? 'Completed successfully'
                  : response.message,
            );
          }
        },
        (failure) async {
          if (!mounted) return;
          _finishFailure(failure);
        },
      );
    } catch (_) {
      if (!mounted) return;
      _finishFailure(
        const Failure(
          'The requested action could not be completed.',
          code: 'unexpected_error',
        ),
      );
    }
  }

  void _handleBackendEvent(AppEvent event) {
    if (event is! ApplicationEvent || !mounted) return;
    if (_handleVoiceEvent(event)) return;
    if (_handleSpeechEvent(event)) return;
    if (event.type == 'browser.disposed') {
      if (_busy) {
        _idleTimer?.cancel();
        _setState(
          AiCoreState.idle,
          title: 'Waiting for your request',
          agent: 'Assistant Core',
          progress: 0,
          steps: const [
            _ActionStep('Waiting for input', _ActionStepStatus.pending),
          ],
        );
        _busy = false;
      }
      return;
    }
    if (!_busy) return;
    if (event.type == 'orchestrator.command.selected') {
      final applicationId = event.data['application_id'];
      final host = event.data['host'];
      _activeTarget = applicationId is String
          ? _applicationDisplayName(applicationId)
          : host is String
          ? host
          : 'requested action';
      final action = event.data['action'];
      if (action == 'open_url' || action == 'initialize_browser') {
        _workspace = _Workspace.browser;
      }
      _setState(
        AiCoreState.thinking,
        title: 'Request understood',
        agent: event.data['agent'] as String? ?? 'AI Orchestrator',
        progress: .38,
        steps: const [
          _ActionStep('Understand request', _ActionStepStatus.complete),
          _ActionStep('Select agent', _ActionStepStatus.active),
          _ActionStep('Execute action', _ActionStepStatus.pending),
        ],
      );
      return;
    }
    if (event.type == 'browser.navigation.requested') {
      final host = event.data['host'];
      _activeTarget = host is String ? host : 'current page';
      _setState(
        AiCoreState.thinking,
        title: 'Preparing browser navigation',
        agent: 'Browser Agent',
        progress: .38,
        steps: const [
          _ActionStep('Validate address', _ActionStepStatus.complete),
          _ActionStep('Authorize navigation', _ActionStepStatus.active),
          _ActionStep('Load page', _ActionStepStatus.pending),
        ],
      );
      return;
    }
    if (event.type == 'browser.created') {
      _activity.insert(
        0,
        _ActivityItem('Browser created', 'Browser Agent', 'Now'),
      );
      return;
    }
    if (event.type == 'browser.ready') {
      _activity.insert(
        0,
        _ActivityItem('Browser initialized', 'Browser Agent', 'Now'),
      );
      return;
    }
    if (event.type == 'browser.navigation.started') {
      _activity.insert(
        0,
        _ActivityItem('Opening $_activeTarget', 'Browser Agent', 'Now'),
      );
      _setState(
        AiCoreState.executing,
        title: 'Opening $_activeTarget',
        agent: 'Browser Agent',
        progress: .72,
        steps: const [
          _ActionStep('Validate address', _ActionStepStatus.complete),
          _ActionStep('Authorize navigation', _ActionStepStatus.complete),
          _ActionStep('Load page', _ActionStepStatus.active),
        ],
      );
      return;
    }
    if (event.type == 'browser.navigation.completed') {
      final title = event.data['title'];
      final message = title is String && title.trim().isNotEmpty
          ? '${title.trim()} loaded'
          : '$_activeTarget loaded';
      _finishSuccess(title: message);
      return;
    }
    if (event.type == 'browser.navigation.failed') {
      _finishFailure(
        Failure(
          'The page could not be loaded.',
          code:
              event.data['failure_code'] as String? ??
              'browser_navigation_failed',
        ),
      );
      return;
    }
    if (event.type == 'tool.started') {
      final toolId = event.data['tool_id'];
      if (toolId == 'browser.embedded.control') return;
      final actionTitle = toolId == 'browser.open_url'
          ? 'Opening web address'
          : 'Opening $_activeTarget';
      _activity.insert(0, _ActivityItem(actionTitle, 'CronyX', 'Now'));
      _setState(
        AiCoreState.executing,
        title: 'Running requested action',
        agent: toolId == 'browser.open_url' ? 'Browser Agent' : 'PC Agent',
        progress: .68,
        steps: const [
          _ActionStep('Understand request', _ActionStepStatus.complete),
          _ActionStep('Select agent', _ActionStepStatus.complete),
          _ActionStep('Execute action', _ActionStepStatus.active),
          _ActionStep('Verify result', _ActionStepStatus.pending),
        ],
      );
    }
  }

  bool _handleVoiceEvent(ApplicationEvent event) {
    if (!event.type.startsWith('voice.')) return false;
    switch (event.type) {
      case 'voice.wake.detected':
      case 'voice.listening.started':
        _idleTimer?.cancel();
        _busy = true;
        _setState(
          AiCoreState.listening,
          title: 'Listening for your request',
          agent: 'CronyX Voice',
          progress: .1,
          steps: const [_ActionStep('Listening', _ActionStepStatus.active)],
        );
      case 'voice.verification.started':
        _busy = true;
        _setState(
          AiCoreState.thinking,
          title: 'Recognizing your voice',
          agent: 'CronyX Voice',
          progress: .3,
          steps: const [
            _ActionStep('Verify speaker', _ActionStepStatus.active),
          ],
        );
      case 'voice.thinking':
      case 'voice.transcript.ready':
        _busy = true;
        _setState(
          AiCoreState.thinking,
          title: 'Understanding your request',
          agent: 'AI Orchestrator',
          progress: .4,
          steps: const [
            _ActionStep('Understand request', _ActionStepStatus.active),
          ],
        );
      case 'voice.access.locked':
        _setState(
          AiCoreState.error,
          title: 'Voice access remains locked',
          agent: 'CronyX Voice',
          progress: .2,
          steps: const [
            _ActionStep('Speaker not verified', _ActionStepStatus.error),
          ],
        );
      default:
      // Remaining voice events are non-visual lifecycle/security telemetry.
    }
    return true;
  }

  void _finishSuccess({String title = 'Completed successfully'}) {
    if (!mounted) return;
    _setState(
      AiCoreState.success,
      title: title,
      agent: 'Assistant Core',
      progress: 1,
      steps: const [
        _ActionStep('Understand request', _ActionStepStatus.complete),
        _ActionStep('Plan response', _ActionStepStatus.complete),
        _ActionStep('Execute action', _ActionStepStatus.complete),
        _ActionStep('Deliver output', _ActionStepStatus.complete),
      ],
    );
    _activity.insert(0, _ActivityItem(title, 'System', 'Now'));
    final speechSynthesizer = widget.speechSynthesizer;
    if (speechSynthesizer == null) {
      _scheduleIdle();
    } else {
      final resultToTts = Stopwatch()..start();
      unawaited(speechSynthesizer.speak(title));
      debugPrint(
        '[TTS] command_result_to_request '
        '${resultToTts.elapsedMicroseconds / 1000} ms',
      );
    }
  }

  bool _handleSpeechEvent(ApplicationEvent event) {
    if (!event.type.startsWith('tts.')) return false;
    if (event.type == 'tts.playback.started') {
      _idleTimer?.cancel();
      _busy = true;
      _setState(
        AiCoreState.speaking,
        title: _actionTitle,
        agent: 'CronyX Voice',
        progress: 1,
        steps: const [
          _ActionStep('Action completed', _ActionStepStatus.complete),
          _ActionStep('Speaking response', _ActionStepStatus.active),
        ],
      );
      return true;
    }
    if (event.type == 'tts.playback.completed' ||
        event.type == 'tts.playback.stopped' ||
        event.type == 'tts.failed') {
      if (_busy || _coreController.state == AiCoreState.speaking) {
        if (event.type == 'tts.failed') {
          _activity.insert(
            0,
            _ActivityItem('Voice response unavailable', 'CronyX Voice', 'Now'),
          );
        }
        _returnToIdle();
      }
      return true;
    }
    // Initialization, generation, and disposal are internal lifecycle events.
    return true;
  }

  void _finishFailure(Failure failure) {
    final title = switch (failure.code) {
      'application_not_found' ||
      'launch_failed' => '$_activeTarget could not be opened',
      'permission_denied' => 'Permission was denied for this action',
      'invalid_url' => 'That web address is not valid',
      'unsupported_command' => 'That command is not supported yet',
      _ => 'The requested action could not be completed',
    };
    _setState(
      AiCoreState.error,
      title: title,
      agent: 'System',
      progress: .35,
      steps: const [
        _ActionStep('Understand request', _ActionStepStatus.complete),
        _ActionStep('Execute action', _ActionStepStatus.error),
      ],
    );
    _activity.insert(0, _ActivityItem(title, 'System', 'Now'));
    _scheduleIdle();
  }

  void _scheduleIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      _setState(
        AiCoreState.idle,
        title: 'Waiting for your request',
        agent: 'Assistant Core',
        progress: 0,
        steps: const [
          _ActionStep('Waiting for input', _ActionStepStatus.pending),
        ],
      );
      _busy = false;
      _commandFocus.requestFocus();
    });
  }

  void _returnToIdle() {
    if (!mounted) return;
    _idleTimer?.cancel();
    _setState(
      AiCoreState.idle,
      title: 'Waiting for your request',
      agent: 'Assistant Core',
      progress: 0,
      steps: const [
        _ActionStep('Waiting for input', _ActionStepStatus.pending),
      ],
    );
    _busy = false;
    _commandFocus.requestFocus();
  }

  void _runQuickAction(String label) {
    if (_busy) return;
    _commandController.text = label;
    _submitCommand(label);
  }

  Future<void> _selectWorkspace(_Workspace workspace) async {
    await _browserSessionTransition;
    final previous = _workspace;
    if (previous != workspace) setState(() => _workspace = workspace);
    if (previous == _Workspace.browser && workspace == _Workspace.core) {
      if (widget.browserController?.state.isInitialized ?? false) {
        if (mounted) setState(() => _busy = true);
        final transition = _disposeBrowserSession();
        _browserSessionTransition = transition;
        await transition;
        if (identical(_browserSessionTransition, transition)) {
          _browserSessionTransition = null;
        }
      }
      return;
    }
    if (workspace == _Workspace.browser &&
        widget.browserController != null &&
        !widget.browserController!.state.isInitialized &&
        !_busy) {
      await _executeBrowserCommand(
        const InitializeBrowserCommand(),
        target: 'CronyX Browser',
      );
    }
  }

  Future<void> _disposeBrowserSession() async {
    final result = await widget.orchestrator.executeCommand(
      const DisposeBrowserCommand(),
    );
    if (!mounted) return;
    result.fold((_) => setState(() => _busy = false), (failure) {
      _busy = false;
      _finishFailure(failure);
    });
  }

  Future<void> _executeBrowserCommand(
    OrchestratorCommand command, {
    required String target,
  }) async {
    if (_busy) return;
    _idleTimer?.cancel();
    setState(() {
      _busy = true;
      _activeTarget = target;
    });
    _setState(
      AiCoreState.thinking,
      title: 'Preparing browser action',
      agent: 'Browser Agent',
      progress: .2,
      steps: const [
        _ActionStep('Prepare action', _ActionStepStatus.active),
        _ActionStep('Execute action', _ActionStepStatus.pending),
      ],
    );
    final result = await widget.orchestrator.executeCommand(command);
    if (!mounted) return;
    result.fold((response) {
      if (response.data['awaiting_page_load'] != true) {
        _finishSuccess(title: response.message);
      }
    }, _finishFailure);
  }

  Future<void> _navigateBrowser(Uri url) =>
      _executeBrowserCommand(OpenUrlCommand(url: url), target: url.host);

  Future<void> _browserBack() => _executeBrowserCommand(
    const BrowserBackCommand(),
    target: 'previous page',
  );

  Future<void> _browserForward() => _executeBrowserCommand(
    const BrowserForwardCommand(),
    target: 'next page',
  );

  Future<void> _browserReload() => _executeBrowserCommand(
    const BrowserReloadCommand(),
    target: 'current page',
  );

  void _toggleListening() {
    if (_busy) return;
    final voiceAssistant = widget.voiceAssistant;
    if (voiceAssistant != null) {
      if (voiceAssistant.wakeMonitoring) {
        unawaited(voiceAssistant.stopListening());
        _returnToIdle();
      } else {
        unawaited(voiceAssistant.startWakeMonitoring());
      }
      return;
    }
    if (_coreController.state == AiCoreState.listening) {
      _setState(
        AiCoreState.idle,
        title: 'Waiting for your request',
        agent: 'Assistant Core',
        progress: 0,
        steps: const [
          _ActionStep('Waiting for input', _ActionStepStatus.pending),
        ],
      );
      return;
    }

    _setState(
      AiCoreState.listening,
      title: 'Listening for your request',
      agent: 'Assistant Core',
      progress: .05,
      steps: const [_ActionStep('Waiting for input', _ActionStepStatus.active)],
    );
  }

  void _setState(
    AiCoreState state, {
    required String title,
    required String agent,
    required double progress,
    required List<_ActionStep> steps,
  }) {
    _coreController.setState(state);
    widget.onCoreStateChanged?.call(state);
    setState(() {
      _actionTitle = title;
      _actionAgent = agent;
      _progress = progress;
      _steps = steps;
    });
  }

  String _applicationDisplayName(String applicationId) =>
      switch (applicationId) {
        'chrome' => 'Google Chrome',
        'edge' => 'Microsoft Edge',
        'notepad' => 'Notepad',
        'calculator' => 'Calculator',
        'file_explorer' => 'File Explorer',
        'settings' => 'Windows Settings',
        'task_manager' => 'Task Manager',
        _ => 'requested application',
      };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _CronyxColors.background,
    body: SafeArea(
      top: false,
      bottom: false,
      child: Stack(
        children: [
          const Positioned.fill(child: _CronyxAtmosphere()),
          Column(
            children: [
              const _TopBar(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 1500;
                    final leftWidth = narrow ? 210.0 : 236.0;
                    final rightWidth = narrow ? 270.0 : 300.0;

                    return Row(
                      children: [
                        SizedBox(
                          width: leftWidth,
                          child: _Sidebar(
                            selected: _workspace,
                            controller: _coreController,
                            activeAgent: _actionAgent,
                            onSelect: _selectWorkspace,
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(child: _buildWorkspace()),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: _CommandBar(
                                  controller: _coreController,
                                  compact: constraints.maxHeight < 700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: rightWidth,
                          child: _RightPanel(
                            actionState: _coreController.state.name
                                .toUpperCase(),
                            actionTitle: _actionTitle,
                            actionAgent: _actionAgent,
                            progress: _progress,
                            steps: _steps,
                            activity: _activity,
                            onQuickAction: _runQuickAction,
                            browserMode: _workspace == _Workspace.browser,
                            onBrowserBack: _browserBack,
                            onBrowserReload: _browserReload,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildWorkspace() {
    if (_workspace == _Workspace.core) {
      return _CoreWorkspace(controller: _coreController);
    }
    final browserController = widget.browserController;
    final surfaceBuilder = widget.browserSurfaceBuilder;
    if (browserController == null || surfaceBuilder == null) {
      return const Center(
        child: Text(
          'CronyX Browser is unavailable.',
          style: _Styles.mutedSmall,
        ),
      );
    }
    return CronyxBrowserWorkspace(
      controller: browserController,
      surfaceBuilder: surfaceBuilder,
      palette: const CronyxBrowserPalette(
        background: _CronyxColors.background,
        panel: Color(0xD9080C12),
        border: _CronyxColors.border,
        borderStrong: _CronyxColors.borderStrong,
        primary: Color(0xFFE9F4FF),
        secondary: Color(0xFF9BAFBD),
        muted: _CronyxColors.muted,
        accent: _CronyxColors.cyan,
        error: _CronyxColors.error,
      ),
      onNavigate: _navigateBrowser,
      onBack: _browserBack,
      onForward: _browserForward,
      onReload: _browserReload,
    );
  }
}

enum _Workspace { core, browser }

class _CronyxAtmosphere extends StatelessWidget {
  const _CronyxAtmosphere();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const CustomPaint(painter: _HtmlAtmospherePainter()),
      ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => RadialGradient(
          center: const Alignment(0, -.18),
          radius: .92,
          colors: const [Colors.white, Colors.white, Colors.transparent],
          stops: const [0, .58, 1],
        ).createShader(rect),
        child: const CustomPaint(painter: _HtmlGridPainter()),
      ),
    ],
  );
}

class _HtmlAtmospherePainter extends CustomPainter {
  const _HtmlAtmospherePainter();

  void _ellipseGlow(
    Canvas canvas,
    Size size,
    Offset center,
    double rx,
    double ry,
    Color color,
    double stop,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(rx, ry);
    final shader = RadialGradient(
      colors: [color, Colors.transparent],
      stops: [0, stop],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1));
    canvas.drawCircle(Offset.zero, 1, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(_CronyxColors.background, BlendMode.srcOver);
    // Exact HTML atmosphere: a broad cool-blue center glow plus a softer
    // lower vignette. The scaling creates the same elliptical falloff as CSS.
    // Exact HTML values:
    // radial-gradient(ellipse 900px 500px at 50% 38%, rgba(30,70,110,.22), transparent 60%)
    // radial-gradient(ellipse 1400px 900px at 50% 100%, rgba(10,30,50,.35), transparent 70%)
    _ellipseGlow(
      canvas,
      size,
      Offset(size.width * .50, size.height * .38),
      450,
      250,
      const Color(0x381E466E),
      .60,
    );
    _ellipseGlow(
      canvas,
      size,
      Offset(size.width * .50, size.height),
      700,
      450,
      const Color(0x590A1E32),
      .70,
    );
  }

  @override
  bool shouldRepaint(covariant _HtmlAtmospherePainter oldDelegate) => false;
}

class _HtmlGridPainter extends CustomPainter {
  const _HtmlGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x0C78AADF)
      ..strokeWidth = 1;
    const spacing = 42.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HtmlGridPainter oldDelegate) => false;
}

class _TopBar extends StatefulWidget {
  const _TopBar();

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  late DateTime _now;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x99080C12), Color(0x5905080C)],
      ),
      border: Border(bottom: BorderSide(color: _CronyxColors.border)),
    ),
    child: Row(
      children: [
        const Text('CRONYX AI OS', style: _Styles.brand),
        const SizedBox(width: 9),
        const Text('v1.0.0', style: _Styles.mutedSmall),
        Expanded(
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_formatClock(_now), style: _Styles.topTime),
                const SizedBox(width: 10),
                Text('â€¢', style: _Styles.topSeparator),
                const SizedBox(width: 10),
                Text(_formatDate(_now), style: _Styles.topDate),
              ],
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: _CronyxColors.success,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: _CronyxColors.success, blurRadius: 8),
                ],
              ),
            ),
            const SizedBox(width: 7),
            const Text('System Ready', style: _Styles.topStatus),
            const SizedBox(width: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                _WindowDot(border: Color(0x664FB8FF)),
                SizedBox(width: 6),
                _WindowDot(border: Color(0x6655E0A2)),
                SizedBox(width: 6),
                _WindowDot(border: Color(0x66FF6A6A)),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.controller,
    required this.activeAgent,
    required this.onSelect,
  });

  final _Workspace selected;
  final AiCoreController controller;
  final String activeAgent;
  final ValueChanged<_Workspace> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x80080C12), Color(0x4D05080C)],
      ),
      border: Border(right: BorderSide(color: _CronyxColors.border)),
    ),
    padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
    child: LayoutBuilder(
      builder: (context, constraints) {
        const compact = false;
        const navGap = 4.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _NavItem(
                    glyph: _HtmlGlyph.core,
                    title: 'Core',
                    subtitle: 'AI Brain',
                    selected: selected == _Workspace.core,
                    compact: compact,
                    onTap: () => onSelect(_Workspace.core),
                  ),
                  SizedBox(height: navGap),
                  _NavItem(
                    glyph: _HtmlGlyph.globe,
                    title: 'Browser',
                    subtitle: 'Web Agent',
                    compact: compact,
                    selected: selected == _Workspace.browser,
                    onTap: () => onSelect(_Workspace.browser),
                  ),
                  SizedBox(height: navGap),
                  _NavItem(
                    glyph: _HtmlGlyph.pc,
                    title: 'PC',
                    subtitle: 'System Agent',
                    compact: compact,
                  ),
                  SizedBox(height: navGap),
                  _NavItem(
                    glyph: _HtmlGlyph.folder,
                    title: 'Files',
                    subtitle: 'File Manager',
                    compact: compact,
                  ),
                  SizedBox(height: navGap),
                  _NavItem(
                    glyph: _HtmlGlyph.tasks,
                    title: 'Tasks',
                    subtitle: 'Task Manager',
                    compact: compact,
                  ),
                  SizedBox(height: navGap),
                  _NavItem(
                    glyph: _HtmlGlyph.memory,
                    title: 'Memory',
                    subtitle: 'Knowledge Base',
                    compact: compact,
                  ),
                  SizedBox(height: navGap),
                  _NavItem(
                    glyph: _HtmlGlyph.agents,
                    title: 'Agents',
                    subtitle: 'All Agents',
                    compact: compact,
                  ),
                  SizedBox(height: navGap),
                  _NavItem(
                    glyph: _HtmlGlyph.settings,
                    title: 'Settings',
                    subtitle: 'Preferences',
                    compact: compact,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _LivingCoreSidebar(
              controller: controller,
              activeAgent: activeAgent,
              compact: constraints.maxHeight < 760,
            ),
          ],
        );
      },
    ),
  );
}

class _LivingCoreSidebar extends StatelessWidget {
  const _LivingCoreSidebar({
    required this.controller,
    required this.activeAgent,
    required this.compact,
  });

  final AiCoreController controller;
  final String activeAgent;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('living-core-sidebar'),
    padding: EdgeInsets.fromLTRB(10, compact ? 4 : 10, 10, compact ? 4 : 10),
    decoration: BoxDecoration(
      color: const Color(0x05FFFFFF),
      border: Border.all(color: _CronyxColors.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('LIVING CORE', style: _Styles.section),
          Center(
            child: SizedBox.square(
              dimension: compact ? 128 : 150,
              child: AiCore(
                controller: controller,
                animationEnabled: true,
                particleDensity: .2,
              ),
            ),
          ),
          Row(
            children: [
              _StatusDot(active: controller.state != AiCoreState.idle),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  controller.state.name.toUpperCase(),
                  key: const Key('living-core-state'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _Styles.panelState,
                ),
              ),
            ],
          ),
          if (!compact) const SizedBox(height: 3),
          Text(
            activeAgent,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _Styles.mutedTiny,
          ),
        ],
      ),
    ),
  );
}

// Preserved from the approved shell for a future non-browser status surface.
// ignore: unused_element
class _SidebarStatus extends StatelessWidget {
  const _SidebarStatus({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x05FFFFFF),
          border: Border.all(color: _CronyxColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('SYSTEM LOAD', style: _Styles.mutedTiny),
                Text('23%', style: _Styles.mutedTiny),
              ],
            ),
            const SizedBox(height: 2),
            const _Sparkline(),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('MEMORY', style: _Styles.mutedTiny),
                Text('5.1 GB / 16 GB', style: _Styles.mutedTiny),
              ],
            ),
            const SizedBox(height: 6),
            const _Meter(progress: .32),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: const Color(0x05FFFFFF),
          border: Border.all(color: _CronyxColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment(-.3, -.4),
                  colors: [Color(0xFF6FD0FF), Color(0xFF2D6FB0)],
                ),
              ),
              child: const Center(
                child: Text(
                  'C',
                  style: TextStyle(
                    color: Color(0xFF04121C),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CronyX User', style: _Styles.secondary),
                  SizedBox(height: 2),
                  Text('Local Profile', style: _Styles.mutedTiny),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: _CronyxColors.muted,
            ),
          ],
        ),
      ),
    ],
  );
}

class _Sparkline extends StatelessWidget {
  const _Sparkline();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 22,
    width: double.infinity,
    child: CustomPaint(painter: _SparklinePainter()),
  );
}

class _SparklinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final points = <Offset>[
      Offset(0, 16),
      Offset(size.width * .075, 12),
      Offset(size.width * .15, 15),
      Offset(size.width * .225, 8),
      Offset(size.width * .30, 13),
      Offset(size.width * .375, 6),
      Offset(size.width * .45, 11),
      Offset(size.width * .525, 9),
      Offset(size.width * .60, 14),
      Offset(size.width * .675, 7),
      Offset(size.width * .75, 12),
      Offset(size.width * .825, 9),
      Offset(size.width * .90, 13),
      Offset(size.width, 8),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _CronyxColors.cyan.withValues(alpha: .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => false;
}

class _Meter extends StatelessWidget {
  const _Meter({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: LinearProgressIndicator(
      value: progress,
      minHeight: 4,
      backgroundColor: _CronyxColors.track,
      valueColor: const AlwaysStoppedAnimation(_CronyxColors.cyan),
    ),
  );
}

enum _HtmlGlyph {
  core,
  globe,
  pc,
  folder,
  tasks,
  memory,
  agents,
  settings,
  terminal,
  addAgent,
  database,
  welcome,
  mic,
  send,
  wave,
  play,
  user,
  shield,
}

class _LineGlyph extends StatelessWidget {
  const _LineGlyph(this.glyph, {required this.color, this.size = 16});
  final _HtmlGlyph glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _LineGlyphPainter(glyph, color),
  );
}

class _LineGlyphPainter extends CustomPainter {
  const _LineGlyphPainter(this.glyph, this.color);
  final _HtmlGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.55
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final c = Offset(size.width / 2, size.height / 2);
    final s = size.shortestSide;
    final k = s / 24;
    Offset pt(double x, double y) => Offset(x * k, y * k);

    switch (glyph) {
      case _HtmlGlyph.core:
        canvas.drawCircle(c, 3 * k, p);
        canvas.drawCircle(c, 8 * k, p..color = color.withValues(alpha: .55));
      case _HtmlGlyph.globe:
        canvas.drawCircle(c, 9 * k, p);
        canvas.drawLine(pt(3, 12), pt(21, 12), p);
        canvas.drawOval(
          Rect.fromCenter(center: c, width: 9 * k, height: 18 * k),
          p,
        );
      case _HtmlGlyph.pc:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(3 * k, 4 * k, 18 * k, 12 * k),
            Radius.circular(1.5 * k),
          ),
          p,
        );
        canvas.drawLine(pt(8, 20), pt(16, 20), p);
        canvas.drawLine(pt(12, 16), pt(12, 20), p);
      case _HtmlGlyph.folder:
        final path = Path()
          ..moveTo(3 * k, 7 * k)
          ..lineTo(3 * k, 18 * k)
          ..lineTo(21 * k, 18 * k)
          ..lineTo(21 * k, 8 * k)
          ..lineTo(12 * k, 8 * k)
          ..lineTo(10 * k, 6 * k)
          ..lineTo(4 * k, 6 * k)
          ..close();
        canvas.drawPath(path, p);
      case _HtmlGlyph.tasks:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(4 * k, 4 * k, 16 * k, 16 * k),
            Radius.circular(2 * k),
          ),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(8 * k, 12 * k)
            ..lineTo(10.5 * k, 14.5 * k)
            ..lineTo(16 * k, 9 * k),
          p,
        );
      case _HtmlGlyph.memory:
        final path = Path()
          ..moveTo(9 * k, 4 * k)
          ..cubicTo(6 * k, 4 * k, 5 * k, 6 * k, 5 * k, 9 * k)
          ..cubicTo(3.5 * k, 9 * k, 3.5 * k, 13 * k, 5 * k, 14 * k)
          ..cubicTo(5 * k, 17 * k, 7 * k, 19 * k, 10 * k, 19 * k)
          ..lineTo(12 * k, 19 * k)
          ..lineTo(12 * k, 5 * k)
          ..close();
        canvas.drawPath(path, p);
        canvas.drawPath(
          Path()
            ..moveTo(15 * k, 4 * k)
            ..cubicTo(18 * k, 4 * k, 19 * k, 6 * k, 19 * k, 9 * k)
            ..cubicTo(20.5 * k, 9 * k, 20.5 * k, 13 * k, 19 * k, 14 * k)
            ..cubicTo(19 * k, 17 * k, 17 * k, 19 * k, 14 * k, 19 * k),
          p,
        );
      case _HtmlGlyph.agents:
        canvas.drawCircle(pt(7, 7), 3 * k, p);
        canvas.drawCircle(pt(17, 7), 3 * k, p);
        canvas.drawCircle(pt(12, 17), 3 * k, p);
        canvas.drawLine(pt(9, 8.5), pt(11, 15), p);
        canvas.drawLine(pt(15, 8.5), pt(13, 15), p);
      case _HtmlGlyph.settings:
        canvas.drawCircle(c, 3 * k, p);
        canvas.drawCircle(c, 8 * k, p);
        for (int i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          canvas.drawLine(
            Offset(c.dx + 6.5 * k * math.cos(a), c.dy + 6.5 * k * math.sin(a)),
            Offset(c.dx + 9 * k * math.cos(a), c.dy + 9 * k * math.sin(a)),
            p,
          );
        }
      case _HtmlGlyph.terminal:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(3 * k, 4 * k, 18 * k, 16 * k),
            Radius.circular(2 * k),
          ),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(7 * k, 9 * k)
            ..lineTo(10 * k, 12 * k)
            ..lineTo(7 * k, 15 * k),
          p,
        );
        canvas.drawLine(pt(12, 15), pt(16, 15), p);
      case _HtmlGlyph.addAgent:
        canvas.drawCircle(pt(12, 8), 3.5 * k, p);
        canvas.drawArc(
          Rect.fromLTWH(6 * k, 13 * k, 12 * k, 8 * k),
          math.pi,
          math.pi,
          false,
          p,
        );
        canvas.drawLine(pt(18, 6), pt(18, 12), p);
        canvas.drawLine(pt(15, 9), pt(21, 9), p);
      case _HtmlGlyph.database:
        canvas.drawOval(Rect.fromLTWH(5 * k, 4 * k, 14 * k, 5 * k), p);
        canvas.drawPath(
          Path()
            ..moveTo(5 * k, 6.5 * k)
            ..lineTo(5 * k, 18 * k)
            ..cubicTo(5 * k, 20 * k, 19 * k, 20 * k, 19 * k, 18 * k)
            ..lineTo(19 * k, 6.5 * k),
          p,
        );
        canvas.drawArc(
          Rect.fromLTWH(5 * k, 10 * k, 14 * k, 5 * k),
          0,
          math.pi,
          false,
          p,
        );
      case _HtmlGlyph.welcome:
        canvas.drawCircle(c, 9 * k, p);
        canvas.drawCircle(pt(12, 10), 2 * k, p);
        canvas.drawArc(
          Rect.fromLTWH(7 * k, 11 * k, 10 * k, 7 * k),
          0,
          math.pi,
          false,
          p,
        );
      case _HtmlGlyph.mic:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(9 * k, 3 * k, 6 * k, 11 * k),
            Radius.circular(3 * k),
          ),
          p,
        );
        canvas.drawArc(
          Rect.fromLTWH(5 * k, 7 * k, 14 * k, 11 * k),
          0,
          math.pi,
          false,
          p,
        );
        canvas.drawLine(pt(12, 18), pt(12, 21), p);
        canvas.drawLine(pt(8, 21), pt(16, 21), p);
      case _HtmlGlyph.send:
        // Matches the final HTML command-bar send SVG:
        // <path d="M12 19V5M5 12l7-7 7 7"/>
        canvas.drawLine(pt(12, 19), pt(12, 5), p);
        canvas.drawLine(pt(5, 12), pt(12, 5), p);
        canvas.drawLine(pt(12, 5), pt(19, 12), p);
      case _HtmlGlyph.wave:
        canvas.drawLine(pt(3, 15), pt(7, 15), p);
        canvas.drawLine(pt(7, 15), pt(9, 8), p);
        canvas.drawLine(pt(9, 8), pt(11, 17), p);
        canvas.drawLine(pt(11, 17), pt(13, 6), p);
        canvas.drawLine(pt(13, 6), pt(15, 15), p);
        canvas.drawLine(pt(15, 15), pt(21, 15), p);
      case _HtmlGlyph.play:
        canvas.drawCircle(c, 9 * k, p);
        canvas.drawPath(
          Path()
            ..moveTo(10 * k, 8 * k)
            ..lineTo(16 * k, 12 * k)
            ..lineTo(10 * k, 16 * k)
            ..close(),
          p,
        );
      case _HtmlGlyph.user:
        canvas.drawCircle(pt(12, 8), 3 * k, p);
        canvas.drawArc(
          Rect.fromLTWH(6 * k, 13 * k, 12 * k, 8 * k),
          math.pi,
          math.pi,
          false,
          p,
        );
      case _HtmlGlyph.shield:
        final path = Path()
          ..moveTo(12 * k, 3 * k)
          ..lineTo(19 * k, 6 * k)
          ..lineTo(19 * k, 12 * k)
          ..cubicTo(19 * k, 16 * k, 16 * k, 19 * k, 12 * k, 21 * k)
          ..cubicTo(8 * k, 19 * k, 5 * k, 16 * k, 5 * k, 12 * k)
          ..lineTo(5 * k, 6 * k)
          ..close();
        canvas.drawPath(path, p);
        canvas.drawPath(
          Path()
            ..moveTo(9 * k, 12 * k)
            ..lineTo(11 * k, 14 * k)
            ..lineTo(15 * k, 10 * k),
          p,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _LineGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.glyph,
    required this.title,
    required this.subtitle,
    this.selected = false,
    this.compact = false,
    this.onTap,
  });

  final _HtmlGlyph glyph;
  final String title;
  final String subtitle;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: Key('nav-${title.toLowerCase()}'),
    onTap: onTap,
    borderRadius: BorderRadius.circular(9),
    child: Container(
      height: 52,
      decoration: BoxDecoration(
        color: selected ? _CronyxColors.selected : Colors.transparent,
        border: Border.all(
          color: selected
              ? _CronyxColors.cyan.withValues(alpha: .38)
              : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(9),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: _CronyxColors.cyan.withValues(alpha: .08),
                  blurRadius: 14,
                ),
              ]
            : const [],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? _CronyxColors.cyan.withValues(alpha: .4)
                      : _CronyxColors.border,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: _CronyxColors.cyan.withValues(alpha: .12),
                          blurRadius: 10,
                        ),
                      ]
                    : const [],
              ),
              child: _LineGlyph(
                glyph,
                color: selected ? _CronyxColors.cyan : _CronyxColors.muted,
                size: 14,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: selected ? _Styles.navActive : _Styles.nav,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _Styles.navSub,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CoreWorkspace extends StatelessWidget {
  const _CoreWorkspace({required this.controller});

  final AiCoreController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxHeight < 700;
      return Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: AiCore(controller: controller)),
                Positioned.fill(child: _StateHud(controller: controller)),
              ],
            ),
          ),
          Transform.translate(
            offset: Offset(0, compact ? -96 : -82),
            child: _CoreStatus(controller: controller, compact: compact),
          ),
        ],
      );
    },
  );
}

class _StateHud extends StatelessWidget {
  const _StateHud({required this.controller});

  final AiCoreController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final h = constraints.maxHeight;
      final center = h * .50;
      final gap = h < 420 ? 48.0 : 64.0;
      return Stack(
        children: [
          Positioned(
            left: constraints.maxWidth * .06,
            top: center - gap - 24,
            child: _HudState(
              'LISTENING',
              controller.state == AiCoreState.listening,
              glyph: _HtmlGlyph.wave,
              onTap: () => _selectHudState(context, AiCoreState.listening),
            ),
          ),
          Positioned(
            right: constraints.maxWidth * .06,
            top: center - gap - 24,
            child: _HudState(
              'SPEAKING',
              controller.state == AiCoreState.speaking,
              reverse: true,
              glyph: _HtmlGlyph.wave,
              onTap: () => _selectHudState(context, AiCoreState.speaking),
            ),
          ),
          Positioned(
            left: constraints.maxWidth * .06,
            top: center + gap,
            child: _HudState(
              'THINKING',
              controller.state == AiCoreState.thinking,
              glyph: _HtmlGlyph.memory,
              onTap: () => _selectHudState(context, AiCoreState.thinking),
            ),
          ),
          Positioned(
            right: constraints.maxWidth * .06,
            top: center + gap,
            child: _HudState(
              'EXECUTING',
              controller.state == AiCoreState.executing,
              reverse: true,
              glyph: _HtmlGlyph.play,
              onTap: () => _selectHudState(context, AiCoreState.executing),
            ),
          ),
        ],
      );
    },
  );
}

void _selectHudState(BuildContext context, AiCoreState state) {
  final shell = context.findAncestorStateOfType<_CronyxOsShellState>();
  if (shell == null) return;
  final data = switch (state) {
    AiCoreState.listening => (
      'Listening for your request',
      'Assistant Core',
      .05,
      const [_ActionStep('Waiting for input', _ActionStepStatus.active)],
    ),
    AiCoreState.thinking => (
      'Thinking about your request',
      'AI Orchestrator',
      .28,
      const [
        _ActionStep('Understand request', _ActionStepStatus.active),
        _ActionStep('Plan response', _ActionStepStatus.pending),
      ],
    ),
    AiCoreState.speaking => (
      'Responding to your request',
      'Assistant Core',
      .68,
      const [
        _ActionStep('Process information', _ActionStepStatus.complete),
        _ActionStep('Generate response', _ActionStepStatus.active),
      ],
    ),
    AiCoreState.executing => (
      'Running requested action',
      'AI Orchestrator',
      .62,
      const [
        _ActionStep('Select agent', _ActionStepStatus.complete),
        _ActionStep('Execute action', _ActionStepStatus.active),
        _ActionStep('Verify result', _ActionStepStatus.pending),
      ],
    ),
    _ => (
      'Waiting for your request',
      'Assistant Core',
      0.0,
      const [_ActionStep('Waiting for input', _ActionStepStatus.pending)],
    ),
  };
  shell._setState(
    state,
    title: data.$1,
    agent: data.$2,
    progress: data.$3,
    steps: data.$4,
  );
}

class _HudState extends StatelessWidget {
  const _HudState(
    this.label,
    this.active, {
    required this.glyph,
    required this.onTap,
    this.reverse = false,
  });

  final String label;
  final bool active;
  final bool reverse;
  final _HtmlGlyph glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: reverse
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: _LineGlyph(
            glyph,
            color: active ? _CronyxColors.cyan : _CronyxColors.muted,
            size: 17,
          ),
        ),
      ),
      const SizedBox(height: 5),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: reverse ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: active ? _CronyxColors.cyan : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? _CronyxColors.cyan : _CronyxColors.muted,
                  width: 1.2,
                ),
                boxShadow: active
                    ? [
                        const BoxShadow(
                          color: _CronyxColors.cyan,
                          blurRadius: 8,
                        ),
                      ]
                    : const [],
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: active ? _Styles.hudActive : _Styles.hud),
          ],
        ),
      ),
    ],
  );
}

class _CoreStatus extends StatelessWidget {
  const _CoreStatus({required this.controller, required this.compact});

  final AiCoreController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = controller.state == AiCoreState.success
        ? _CronyxColors.success
        : controller.state == AiCoreState.error
        ? _CronyxColors.error
        : _CronyxColors.cyan;

    // Match the final HTML exactly: wave -> state -> prompt. There is no
    // secondary status line between the state and the prompt.
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 22 : 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WaveBars(color: color),
          const SizedBox(height: 8),
          Text(
            controller.state.name.toUpperCase(),
            style: _Styles.state.copyWith(color: color),
          ),
          const SizedBox(height: 6),
          const Text(
            'How can I assist you today?',
            key: Key('core-prompt'),
            style: _Styles.prompt,
          ),
        ],
      ),
    );
  }
}

class _WaveBars extends StatefulWidget {
  const _WaveBars({required this.color});
  final Color color;

  @override
  State<_WaveBars> createState() => _WaveBarsState();
}

class _WaveBarsState extends State<_WaveBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 14,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(5, (i) {
          final phase = (_controller.value + i * .1) % 1;
          final height = 4 + math.sin(phase * math.pi * 2) * 5 + 5;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Container(
              width: 2.5,
              height: height.clamp(4, 14),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: .75),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    ),
  );
}

class _CommandBar extends StatelessWidget {
  const _CommandBar({required this.controller, required this.compact});

  final AiCoreController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<_CronyxOsShellState>();
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 12 : 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = math.min(680.0, constraints.maxWidth * .86);
              return SizedBox(
                width: width,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(11, 11, 14, 11),
                      decoration: BoxDecoration(
                        color: const Color(0xBF090F16),
                        border: Border.all(color: _CronyxColors.borderStrong),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0D4FB8FF),
                            blurRadius: 0,
                            spreadRadius: 1,
                          ),
                          BoxShadow(
                            color: Color(0x80000000),
                            blurRadius: 40,
                            offset: Offset(0, 10),
                          ),
                          BoxShadow(color: Color(0x143C8CDC), blurRadius: 26),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(30),
                            onTap: shell?._toggleListening,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _CronyxColors.borderStrong,
                                  width: 1.5,
                                ),
                                color: const Color(0x0F4FB8FF),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x384FB8FF),
                                    blurRadius: 18,
                                  ),
                                  BoxShadow(
                                    color: Color(0x144FB8FF),
                                    blurRadius: 12,
                                    spreadRadius: -2,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: _LineGlyph(
                                  _HtmlGlyph.mic,
                                  color: _CronyxColors.cyan,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  key: const Key('command-input'),
                                  controller: shell?._commandController,
                                  focusNode: shell?._commandFocus,
                                  onSubmitted: shell?._submitCommand,
                                  textInputAction: TextInputAction.send,
                                  style: _Styles.input,
                                  decoration: const InputDecoration(
                                    hintText:
                                        'Type a command or ask anything...',
                                    hintStyle: _Styles.inputHint,
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 1),
                                const Text(
                                  'Examples:  "Open Chrome"   Â·   "Show my files"   Â·   "System status"   Â·   "What can you do?"',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _Styles.commandExamples,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          InkWell(
                            key: const Key('command-send'),
                            borderRadius: BorderRadius.circular(30),
                            onTap: shell?._submitCommand,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  center: Alignment(-.3, -.3),
                                  colors: [
                                    Color(0xFF7FD6FF),
                                    Color(0xFF1F7BC4),
                                  ],
                                  stops: [0, .75],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0x734FB8FF),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: _LineGlyph(
                                  _HtmlGlyph.send,
                                  color: Color(0xFF04121C),
                                  size: 17,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          const Text(
            'TIP: You can also speak to CronyX',
            style: _Styles.mutedTiny,
          ),
        ],
      ),
    );
  }
}

class _RightPanel extends StatelessWidget {
  const _RightPanel({
    required this.actionState,
    required this.actionTitle,
    required this.actionAgent,
    required this.progress,
    required this.steps,
    required this.activity,
    required this.onQuickAction,
    required this.browserMode,
    required this.onBrowserBack,
    required this.onBrowserReload,
  });

  final String actionState;
  final String actionTitle;
  final String actionAgent;
  final double progress;
  final List<_ActionStep> steps;
  final List<_ActivityItem> activity;
  final ValueChanged<String> onQuickAction;
  final bool browserMode;
  final Future<void> Function() onBrowserBack;
  final Future<void> Function() onBrowserReload;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x80080C12), Color(0x4D05080C)],
      ),
      border: Border(left: BorderSide(color: _CronyxColors.border)),
    ),
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
    child: ListView(
      padding: EdgeInsets.zero,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            _SectionLabel('LIVE ACTION'),
            Text('CLEAR', style: _Styles.link),
          ],
        ),
        const SizedBox(height: 9),
        _PanelCard(
          live: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusDot(active: actionState != 'IDLE'),
                  const SizedBox(width: 7),
                  Text(actionState, style: _Styles.panelState),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                actionTitle,
                style: _Styles.panelTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(actionAgent, style: _Styles.mutedSmall),
              const SizedBox(height: 12),
              ...steps.map((step) => _ActionStepRow(step: step)),
              const SizedBox(height: 11),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('PROGRESS', style: _Styles.mutedTiny),
                  Text('${(progress * 100).round()}%', style: _Styles.mono),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: _CronyxColors.track,
                  valueColor: const AlwaysStoppedAnimation(_CronyxColors.cyan),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            _SectionLabel('ACTIVITY'),
            Text('VIEW ALL', style: _Styles.link),
          ],
        ),
        const SizedBox(height: 9),
        _PanelCard(
          child: Column(
            children: activity
                .take(5)
                .toList()
                .asMap()
                .entries
                .map(
                  (entry) => _ActivityRow(
                    item: entry.value,
                    last: entry.key == activity.take(5).length - 1,
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        const _SectionLabel('QUICK ACTIONS'),
        const SizedBox(height: 9),
        Column(
          children: browserMode
              ? [
                  _QuickAction(
                    label: 'Go Back',
                    subtitle: 'Browser History',
                    glyph: _HtmlGlyph.globe,
                    onTap: () => unawaited(onBrowserBack()),
                  ),
                  const SizedBox(height: 8),
                  _QuickAction(
                    label: 'Reload',
                    subtitle: 'Current Page',
                    glyph: _HtmlGlyph.globe,
                    onTap: () => unawaited(onBrowserReload()),
                  ),
                ]
              : [
                  _QuickAction(
                    label: 'Open Browser',
                    subtitle: 'Web Agent',
                    glyph: _HtmlGlyph.globe,
                    onTap: () => onQuickAction('Open Browser'),
                  ),
                  const SizedBox(height: 8),
                  _QuickAction(
                    label: 'Open My PC',
                    subtitle: 'System Access',
                    glyph: _HtmlGlyph.pc,
                    onTap: () => onQuickAction('Open My PC'),
                  ),
                  const SizedBox(height: 8),
                  _QuickAction(
                    label: 'Browse Files',
                    subtitle: 'File Manager',
                    glyph: _HtmlGlyph.folder,
                    onTap: () => onQuickAction('Browse Files'),
                  ),
                  const SizedBox(height: 8),
                  _QuickAction(
                    label: 'View Tasks',
                    subtitle: 'Task Manager',
                    glyph: _HtmlGlyph.tasks,
                    onTap: () => onQuickAction('View Tasks'),
                  ),
                ],
        ),
      ],
    ),
  );
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child, this.live = false});

  final Widget child;
  final bool live;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
    decoration: BoxDecoration(
      color: const Color(0x04FFFFFF),
      gradient: live
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x124FB8FF), Color(0x050A1018)],
            )
          : null,
      border: Border.all(
        color: live ? _CronyxColors.borderStrong : _CronyxColors.border,
      ),
      borderRadius: BorderRadius.circular(12),
      boxShadow: live
          ? [const BoxShadow(color: Color(0x0F4FB8FF), blurRadius: 24)]
          : const [],
    ),
    child: child,
  );
}

class _ActionStepRow extends StatelessWidget {
  const _ActionStepRow({required this.step});
  final _ActionStep step;

  @override
  Widget build(BuildContext context) {
    final (icon, color, stateText) = switch (step.status) {
      _ActionStepStatus.complete => (
        Icons.check_rounded,
        _CronyxColors.success,
        'Completed',
      ),
      _ActionStepStatus.active => (
        Icons.circle,
        _CronyxColors.cyan,
        'In Progress',
      ),
      _ActionStepStatus.error => (
        Icons.close_rounded,
        _CronyxColors.error,
        'Error',
      ),
      _ActionStepStatus.pending => (
        Icons.circle_outlined,
        _CronyxColors.muted,
        'Pending',
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              step.label,
              style: step.status == _ActionStepStatus.active
                  ? _Styles.stepActive
                  : _Styles.step,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            stateText,
            style: TextStyle(
              color: color.withValues(
                alpha: step.status == _ActionStepStatus.pending ? .8 : 1,
              ),
              fontSize: 8.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, this.last = false});
  final _ActivityItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final _HtmlGlyph glyph = item.title.contains('Chrome')
        ? _HtmlGlyph.globe
        : item.title.contains('Memory')
        ? _HtmlGlyph.database
        : item.title.contains('Core')
        ? _HtmlGlyph.core
        : item.title.contains('PC')
        ? _HtmlGlyph.pc
        : _HtmlGlyph.welcome;

    final Color iconColor = item.title.contains('Memory')
        ? _CronyxColors.success
        : item.title.contains('Core')
        ? const Color(0xFF9B8CFF)
        : _CronyxColors.cyan;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 13),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: _CronyxColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withValues(alpha: .12),
            ),
            child: _LineGlyph(glyph, color: iconColor, size: 13),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: _Styles.step,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(item.time, style: _Styles.mutedTiny),
                  ],
                ),
                const SizedBox(height: 2),
                Text(item.source, style: _Styles.mutedTiny),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.glyph,
    required this.onTap,
    required this.subtitle,
  });

  final String label;
  final _HtmlGlyph glyph;
  final VoidCallback onTap;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final accent = switch (label) {
      'Browse Files' => _CronyxColors.amber,
      'View Tasks' => _CronyxColors.success,
      'Run Command' => const Color(0xFFFF8A65),
      'Add Agent' => _CronyxColors.purple,
      _ => _CronyxColors.cyan,
    };
    return InkWell(
      key: Key('quick-action-$label'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0x04FFFFFF),
          border: Border.all(color: _CronyxColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _CronyxColors.border),
              ),
              child: _LineGlyph(glyph, color: accent, size: 15),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: _Styles.quick,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: _Styles.quickSub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Preserved from the approved shell for a future dedicated system workspace.
// ignore: unused_element
class _SystemMetric extends StatelessWidget {
  const _SystemMetric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final network = label == 'NETWORK';
    final temp = label == 'TEMP';
    final security = label == 'SECURITY';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 11),
      decoration: BoxDecoration(
        color: const Color(0x04FFFFFF),
        border: Border.all(color: _CronyxColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _Styles.mutedTiny),
          const SizedBox(height: 5),
          if (network) ...[
            const Text(
              'â†‘ 12.4 KB/s',
              style: TextStyle(
                color: _CronyxColors.success,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Text(
              'â†“ 8.7 KB/s',
              style: TextStyle(color: Color(0xFF8FA4B8), fontSize: 9.5),
            ),
          ] else if (security) ...[
            Row(
              children: const [
                _LineGlyph(
                  _HtmlGlyph.shield,
                  color: _CronyxColors.success,
                  size: 12,
                ),
                SizedBox(width: 5),
                Text(
                  'Protected',
                  style: TextStyle(
                    color: _CronyxColors.success,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFFEAF2FB),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 14,
              width: double.infinity,
              child: CustomPaint(painter: _MetricSparkPainter(amber: temp)),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricSparkPainter extends CustomPainter {
  const _MetricSparkPainter({required this.amber});
  final bool amber;
  @override
  void paint(Canvas canvas, Size size) {
    const points = <double>[10, 7, 11, 5, 9, 4, 8, 6, 9];
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final y = points[i];
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = (amber ? _CronyxColors.amber : _CronyxColors.cyan).withValues(
          alpha: .8,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
  }

  @override
  bool shouldRepaint(covariant _MetricSparkPainter oldDelegate) =>
      oldDelegate.amber != amber;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: _Styles.section);
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      color: active ? _CronyxColors.cyan : _CronyxColors.muted,
      shape: BoxShape.circle,
      boxShadow: active
          ? [const BoxShadow(color: _CronyxColors.cyan, blurRadius: 9)]
          : const [],
    ),
  );
}

class _WindowDot extends StatelessWidget {
  const _WindowDot({required this.border});
  final Color border;
  @override
  Widget build(BuildContext context) => Container(
    width: 13,
    height: 13,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: border),
    ),
  );
}

class _ActivityItem {
  const _ActivityItem(this.title, this.source, this.time);
  final String title;
  final String source;
  final String time;
}

class _ActionStep {
  const _ActionStep(this.label, this.status);
  final String label;
  final _ActionStepStatus status;
}

enum _ActionStepStatus { pending, active, complete, error }

class _CronyxColors {
  static const background = Color(0xFF030507);
  static const border = Color(0x2478AADC);
  static const borderStrong = Color(0x666EBEFF);
  static const selected = Color(0x1A3C8CDC);
  static const cyan = Color(0xFF4FB8FF);
  static const muted = Color(0xFF536576);
  static const success = Color(0xFF5DE0A2);
  static const error = Color(0xFFFF687A);
  static const amber = Color(0xFFFFB454);
  static const purple = Color(0xFF9B8CFF);
  static const track = Color(0x0FFFFFFF);
}

class _Styles {
  static const brand = TextStyle(
    color: Color(0xFFE9F4FF),
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.1,
  );
  static const mutedSmall = TextStyle(
    color: Color(0xFF5F7180),
    fontSize: 10,
    letterSpacing: 1.0,
  );
  static const mutedTiny = TextStyle(
    color: Color(0xFF536576),
    fontSize: 8,
    letterSpacing: 1.15,
  );
  static const mono = TextStyle(
    color: Color(0xFF91B8D3),
    fontSize: 9,
    letterSpacing: 1.2,
    fontWeight: FontWeight.w600,
  );
  static const topTime = TextStyle(
    color: Color(0xFFEAF2FB),
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    letterSpacing: .3,
  );
  static const topSeparator = TextStyle(color: Color(0xFF52616F), fontSize: 10);
  static const topDate = TextStyle(color: Color(0xFF8FA4B8), fontSize: 10);
  static const topStatus = TextStyle(
    color: Color(0xFF37E29A),
    fontSize: 10.5,
    letterSpacing: 1.0,
  );
  static const secondary = TextStyle(color: Color(0xFF9BAFBD), fontSize: 11);
  static const nav = TextStyle(
    color: Color(0xFF7C8D9A),
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    letterSpacing: .7,
  );
  static const navActive = TextStyle(
    color: Color(0xFFEAF2FB),
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    letterSpacing: .7,
  );
  static const navSub = TextStyle(
    color: Color(0xFF52616F),
    fontSize: 10.5,
    letterSpacing: .8,
  );
  static const section = TextStyle(
    color: Color(0xFF8FA4B8),
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.42,
  );
  static const link = TextStyle(color: Color(0xFF4FB8FF), fontSize: 10.5);
  static const hud = TextStyle(
    color: Color(0xFF52616F),
    fontSize: 8.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.5,
  );
  static const hudActive = TextStyle(
    color: Color(0xFF8BD4FF),
    fontSize: 8.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
  );
  static const state = TextStyle(
    color: Color(0xFF4FB8FF),
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 3.64,
  );
  static const input = TextStyle(color: Color(0xFFE3F3FF), fontSize: 14.5);
  static const inputHint = TextStyle(color: Color(0xFF8FA4B8), fontSize: 14.5);
  static const prompt = TextStyle(
    color: Color(0xFF8FA4B8),
    fontSize: 15,
    fontWeight: FontWeight.w400,
  );
  static const commandExamples = TextStyle(
    color: Color(0xFF52616F),
    fontSize: 10.5,
  );
  static const panelState = TextStyle(
    color: Color(0xFF8BCFFF),
    fontSize: 9.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
  );
  static const panelTitle = TextStyle(
    color: Color(0xFFD7E8F2),
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
  );
  static const step = TextStyle(color: Color(0xFF8FA4B8), fontSize: 11.5);
  static const stepActive = TextStyle(
    color: Color(0xFFEAF2FB),
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
  );
  static const quick = TextStyle(
    color: Color(0xFFEAF2FB),
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );
  static const quickSub = TextStyle(color: Color(0xFF52616F), fontSize: 9);
}

String _formatClock(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

String _formatDate(DateTime value) {
  const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${weekdays[value.weekday - 1]}, ${months[value.month - 1]} ${value.day}';
}

double mathMin(double a, double b) => a < b ? a : b;
