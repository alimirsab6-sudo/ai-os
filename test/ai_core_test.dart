import 'package:ai_os/ui/world/ai_core/ai_core.dart';
import 'package:ai_os/ui/world/ai_core/ai_core_controller.dart';
import 'package:ai_os/ui/world/ai_core/ai_core_demo_screen.dart';
import 'package:ai_os/ui/world/ai_core/ai_core_renderer.dart';
import 'package:ai_os/ui/world/ai_core/ai_core_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quality levels select distinct ordered shader configurations', () {
    expect(
      AiCoreQuality.values.map((quality) => quality.shaderValue),
      orderedEquals(<double>[0, 1, 2]),
    );
  });

  test('controller defaults target the medium office-hardware profile', () {
    final controller = AiCoreController();
    addTearDown(controller.dispose);

    expect(controller.state, AiCoreState.idle);
    expect(controller.quality, AiCoreQuality.medium);
    expect(controller.mouseInteraction, isTrue);
    expect(controller.intensity, 1);
    expect(controller.speechIntensity, 0.72);
  });

  test('controller supports every visual state transition', () {
    final controller = AiCoreController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    for (final state in AiCoreState.values.skip(1)) {
      controller.setState(state);
      expect(controller.state, state);
    }
    expect(notifications, AiCoreState.values.length - 1);
  });

  test('controller clamps visual and simulated speech intensity', () {
    final controller = AiCoreController();
    addTearDown(controller.dispose);

    controller.setIntensity(9);
    controller.setSpeechIntensity(-2);
    expect(controller.intensity, 1.5);
    expect(controller.speechIntensity, 0);

    controller.setIntensity(0);
    controller.setSpeechIntensity(4);
    expect(controller.intensity, 0.35);
    expect(controller.speechIntensity, 1);
  });

  testWidgets('AiCore constructs the authoritative GPU renderer', (
    tester,
  ) async {
    final controller = AiCoreController(state: AiCoreState.thinking);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AiCore(
          controller: controller,
          size: 320,
          animationEnabled: false,
        ),
      ),
    );

    expect(find.byType(AiCore), findsOneWidget);
    expect(find.byType(AiCoreRenderer), findsOneWidget);
    expect(
      tester
          .widget<AiCoreRenderer>(find.byType(AiCoreRenderer))
          .particleDensity,
      1,
    );
    expect(find.bySemanticsLabel('Living AI Core thinking'), findsOneWidget);
  });

  testWidgets('AI Core semantics follow controller state changes', (
    tester,
  ) async {
    final controller = AiCoreController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AiCore(controller: controller, animationEnabled: false),
      ),
    );

    controller.setState(AiCoreState.speaking);
    await tester.pump();
    expect(find.bySemanticsLabel('Living AI Core speaking'), findsOneWidget);
  });

  testWidgets('demo exposes states, quality, mouse, and speech controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const MaterialApp(home: AiCoreDemoScreen()));

    expect(find.byType(AiCore), findsOneWidget);
    expect(find.text('LIVING CORE // WORLD FOUNDATION'), findsOneWidget);
    for (final state in AiCoreState.values) {
      expect(find.text(state.name.toUpperCase()), findsOneWidget);
    }
    expect(find.text('MOUSE ON'), findsOneWidget);
    expect(find.text('SPEECH'), findsOneWidget);
    expect(find.text('MEDIUM'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
}
