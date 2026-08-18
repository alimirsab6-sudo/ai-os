import 'dart:async';

import 'package:ai_os/agents/pc_agent/pc_agent.dart';
import 'package:ai_os/ai/model_provider/mock_model_provider.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/events/app_event.dart';
import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/windows/applications/application_descriptor.dart';
import 'package:ai_os/tools/windows/applications/application_launcher.dart';
import 'package:ai_os/tools/windows/launch_application_tool.dart';
import 'package:ai_os/ui/shell/cronyx_os_shell.dart';
import 'package:ai_os/ui/world/ai_core/ai_core_state.dart';
import 'package:ai_os/voice/speech_synthesizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pc_agent_fakes.dart';
import 'support/speech_fakes.dart';

final class _ControlledLauncher implements ApplicationLauncher {
  final Completer<Result<ApplicationLaunchReceipt>> completion = Completer();
  int launchCount = 0;
  ResolvedApplication? launchedApplication;

  @override
  Future<Result<ApplicationLaunchReceipt>> launch(
    ResolvedApplication application,
  ) {
    launchCount++;
    launchedApplication = application;
    return completion.future;
  }

  void succeed() {
    final applicationId = launchedApplication?.descriptor.id ?? 'chrome';
    completion.complete(
      Result.success(
        ApplicationLaunchReceipt(applicationId: applicationId, processId: 42),
      ),
    );
  }

  void fail() {
    completion.complete(
      const Result.failure(
        Failure('raw process detail', code: 'launch_failed'),
      ),
    );
  }
}

Orchestrator _createOrchestrator(
  EventBus events, [
  ApplicationLauncher? launcher,
]) {
  if (launcher == null) {
    return Orchestrator(
      modelProvider: const MockModelProvider(),
      events: events,
    );
  }
  final tool = LaunchApplicationTool(
    registry: createApplicationRegistry(),
    launcher: launcher,
    events: events,
  );
  return Orchestrator(
    modelProvider: const MockModelProvider(),
    events: events,
    agents: [
      PcAgent(
        launchApplicationTool: tool,
        authorizer: AllowListPermissionAuthorizer({Permission.execute}),
      ),
    ],
    tools: [tool],
    commandInterpreter: const DeterministicCommandInterpreter(),
  );
}

Widget _desktopShell({
  required Orchestrator orchestrator,
  ValueChanged<AiCoreState>? onCoreStateChanged,
  SpeechSynthesizer? speechSynthesizer,
}) => MaterialApp(
  home: FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 1800,
      height: 1000,
      child: CronyxOsShell(
        orchestrator: orchestrator,
        onCoreStateChanged: onCoreStateChanged,
        speechSynthesizer: speechSynthesizer,
      ),
    ),
  ),
);

void _discardApprovedShellOverflows(WidgetTester tester) {
  final exception = tester.takeException();
  if (exception == null) return;
  expect(
    exception.toString(),
    anyOf(contains('RenderFlex overflowed'), contains('Multiple exceptions')),
  );
}

Future<void> _disposeShell(WidgetTester tester, EventBus events) async {
  await tester.pumpWidget(const SizedBox.shrink());
  _discardApprovedShellOverflows(tester);
  await events.close();
}

void main() {
  testWidgets('AI OS starts on the approved CronyX shell', (tester) async {
    final events = EventBus();
    await tester.pumpWidget(
      _desktopShell(orchestrator: _createOrchestrator(events)),
    );
    _discardApprovedShellOverflows(tester);

    expect(find.byType(CronyxOsShell), findsOneWidget);
    expect(find.text('CRONYX AI OS'), findsOneWidget);
    expect(find.text('LIVE ACTION'), findsOneWidget);
    expect(find.text('QUICK ACTIONS'), findsOneWidget);
    expect(find.text('How can I assist you today?'), findsOneWidget);
    expect(find.text('Waiting for your request'), findsOneWidget);
    await _disposeShell(tester, events);
  });

  testWidgets('command submission drives real lifecycle and activity', (
    tester,
  ) async {
    final events = EventBus();
    final launcher = _ControlledLauncher();
    final states = <AiCoreState>[];
    await tester.pumpWidget(
      _desktopShell(
        orchestrator: _createOrchestrator(events, launcher),
        onCoreStateChanged: states.add,
      ),
    );
    _discardApprovedShellOverflows(tester);

    await tester.enterText(
      find.byKey(const Key('command-input')),
      'Open Chrome',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    _discardApprovedShellOverflows(tester);

    expect(launcher.launchCount, 1);
    expect(
      states,
      containsAllInOrder([AiCoreState.thinking, AiCoreState.executing]),
    );
    expect(find.text('Running requested action'), findsOneWidget);
    expect(find.text('Open Chrome'), findsOneWidget);
    expect(find.text('Opening Google Chrome'), findsOneWidget);

    launcher.succeed();
    await tester.pump();
    _discardApprovedShellOverflows(tester);

    expect(states.last, AiCoreState.success);
    expect(find.text('Google Chrome opened successfully.'), findsWidgets);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('CronyX'), findsOneWidget);
    expect(find.text('System'), findsWidgets);

    await tester.pump(const Duration(milliseconds: 1600));
    _discardApprovedShellOverflows(tester);
    expect(states.last, AiCoreState.idle);
    await _disposeShell(tester, events);
  });

  testWidgets('failed action is sanitized and drives Error then Idle', (
    tester,
  ) async {
    final events = EventBus();
    final launcher = _ControlledLauncher();
    final states = <AiCoreState>[];
    await tester.pumpWidget(
      _desktopShell(
        orchestrator: _createOrchestrator(events, launcher),
        onCoreStateChanged: states.add,
      ),
    );
    _discardApprovedShellOverflows(tester);

    await tester.enterText(
      find.byKey(const Key('command-input')),
      'Open Chrome',
    );
    await tester.tap(find.byKey(const Key('command-send')));
    await tester.pump();
    _discardApprovedShellOverflows(tester);
    launcher.fail();
    await tester.pump();
    _discardApprovedShellOverflows(tester);

    expect(states.last, AiCoreState.error);
    expect(find.text('Google Chrome could not be opened'), findsWidgets);
    expect(find.textContaining('raw process detail'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1600));
    _discardApprovedShellOverflows(tester);
    expect(states.last, AiCoreState.idle);
    await _disposeShell(tester, events);
  });

  testWidgets('Open Browser quick action uses the command pipeline', (
    tester,
  ) async {
    final events = EventBus();
    final launcher = _ControlledLauncher();
    final states = <AiCoreState>[];
    await tester.pumpWidget(
      _desktopShell(
        orchestrator: _createOrchestrator(events, launcher),
        onCoreStateChanged: states.add,
      ),
    );
    _discardApprovedShellOverflows(tester);

    await tester.tap(find.byKey(const Key('quick-action-Open Browser')));
    await tester.pump();
    _discardApprovedShellOverflows(tester);

    expect(launcher.launchCount, 1);
    expect(states, contains(AiCoreState.executing));
    launcher.succeed();
    await tester.pump();
    _discardApprovedShellOverflows(tester);
    expect(states.last, AiCoreState.success);
    await _disposeShell(tester, events);
  });

  testWidgets('Open My PC quick action routes to File Explorer', (
    tester,
  ) async {
    final events = EventBus();
    final launcher = _ControlledLauncher();
    await tester.pumpWidget(
      _desktopShell(orchestrator: _createOrchestrator(events, launcher)),
    );
    _discardApprovedShellOverflows(tester);

    await tester.tap(find.byKey(const Key('quick-action-Open My PC')));
    await tester.pump();
    _discardApprovedShellOverflows(tester);

    expect(launcher.launchedApplication?.descriptor.id, 'file_explorer');
    launcher.succeed();
    await tester.pump();
    _discardApprovedShellOverflows(tester);
    expect(find.text('File Explorer opened successfully.'), findsWidgets);
    await _disposeShell(tester, events);
  });

  testWidgets('Browse Files uses the same controlled File Explorer path', (
    tester,
  ) async {
    final events = EventBus();
    final launcher = _ControlledLauncher();
    await tester.pumpWidget(
      _desktopShell(orchestrator: _createOrchestrator(events, launcher)),
    );
    _discardApprovedShellOverflows(tester);

    await tester.tap(find.byKey(const Key('quick-action-Browse Files')));
    await tester.pump();
    _discardApprovedShellOverflows(tester);

    expect(launcher.launchedApplication?.descriptor.id, 'file_explorer');
    launcher.succeed();
    await tester.pump();
    _discardApprovedShellOverflows(tester);
    expect(find.text('File Explorer opened successfully.'), findsWidgets);
    await _disposeShell(tester, events);
  });

  testWidgets('unimplemented and unsafe quick actions are not exposed', (
    tester,
  ) async {
    final events = EventBus();
    final launcher = _ControlledLauncher();
    await tester.pumpWidget(
      _desktopShell(orchestrator: _createOrchestrator(events, launcher)),
    );
    _discardApprovedShellOverflows(tester);

    expect(find.byKey(const Key('quick-action-Run Command')), findsNothing);
    expect(find.byKey(const Key('quick-action-Add Agent')), findsNothing);
    expect(launcher.launchCount, 0);
    await _disposeShell(tester, events);
  });

  testWidgets('successful command speaks and follows actual playback states', (
    tester,
  ) async {
    final events = EventBus();
    final launcher = _ControlledLauncher();
    final speech = FakeSpeechSynthesizer(events: events);
    final states = <AiCoreState>[];
    await tester.pumpWidget(
      _desktopShell(
        orchestrator: _createOrchestrator(events, launcher),
        speechSynthesizer: speech,
        onCoreStateChanged: states.add,
      ),
    );
    _discardApprovedShellOverflows(tester);

    await tester.enterText(
      find.byKey(const Key('command-input')),
      'Open Chrome',
    );
    await tester.tap(find.byKey(const Key('command-send')));
    await tester.pump();
    launcher.succeed();
    await tester.pump();
    _discardApprovedShellOverflows(tester);

    expect(speech.spokenTexts, ['Google Chrome opened successfully.']);
    expect(
      states,
      containsAllInOrder([AiCoreState.success, AiCoreState.speaking]),
    );
    expect(states.last, AiCoreState.speaking);

    speech.completePlayback();
    await tester.pump();
    expect(states.last, AiCoreState.idle);
    await _disposeShell(tester, events);
  });

  testWidgets('voice failure does not replace successful command result', (
    tester,
  ) async {
    final events = EventBus();
    final launcher = _ControlledLauncher();
    final speech = FakeSpeechSynthesizer(events: events, failSpeech: true);
    final states = <AiCoreState>[];
    await tester.pumpWidget(
      _desktopShell(
        orchestrator: _createOrchestrator(events, launcher),
        speechSynthesizer: speech,
        onCoreStateChanged: states.add,
      ),
    );
    _discardApprovedShellOverflows(tester);

    await tester.enterText(
      find.byKey(const Key('command-input')),
      'Open Chrome',
    );
    await tester.tap(find.byKey(const Key('command-send')));
    await tester.pump();
    launcher.succeed();
    await tester.pump();
    _discardApprovedShellOverflows(tester);

    expect(speech.spokenTexts, ['Google Chrome opened successfully.']);
    expect(states, contains(AiCoreState.success));
    expect(states, isNot(contains(AiCoreState.error)));
    expect(find.text('Google Chrome opened successfully.'), findsWidgets);
    expect(find.text('Voice response unavailable'), findsOneWidget);
    await _disposeShell(tester, events);
  });

  testWidgets('internal debug events are never sent to speech', (tester) async {
    final events = EventBus();
    final speech = FakeSpeechSynthesizer(
      events: events,
      completeImmediately: true,
    );
    await tester.pumpWidget(
      _desktopShell(
        orchestrator: _createOrchestrator(events),
        speechSynthesizer: speech,
      ),
    );
    _discardApprovedShellOverflows(tester);

    events.publish(
      ApplicationEvent(
        type: 'browser.created',
        occurredAt: DateTime.now().toUtc(),
      ),
    );
    events.publish(
      ApplicationEvent(
        type: 'tool.started',
        occurredAt: DateTime.now().toUtc(),
        data: const {'tool_id': 'debug.internal'},
      ),
    );
    await tester.pump();

    expect(speech.spokenTexts, isEmpty);
    await _disposeShell(tester, events);
  });
}
