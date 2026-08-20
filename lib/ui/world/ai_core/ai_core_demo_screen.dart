import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ai_core.dart';
import 'ai_core_controller.dart';
import 'ai_core_state.dart';

class AiCoreDemoScreen extends StatefulWidget {
  const AiCoreDemoScreen({super.key});

  @override
  State<AiCoreDemoScreen> createState() => _AiCoreDemoScreenState();
}

class _AiCoreDemoScreenState extends State<AiCoreDemoScreen> {
  late final AiCoreController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AiCoreController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF010104),
    body: AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => LayoutBuilder(
        builder: (context, constraints) {
          final coreSize = math
              .min(constraints.maxWidth * 0.72, constraints.maxHeight * 0.72)
              .clamp(320.0, 820.0);
          return Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(0, -30),
                    child: AiCore(controller: _controller, size: coreSize),
                  ),
                ),
              ),
              const Positioned(top: 32, left: 38, child: _WorldLabel()),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _DevelopmentControls(controller: _controller),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _WorldLabel extends StatelessWidget {
  const _WorldLabel();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'AI OS',
        style: TextStyle(
          color: Color(0xFFC1B0DB),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 4.5,
        ),
      ),
      SizedBox(height: 7),
      Text(
        'LIVING CORE // WORLD FOUNDATION',
        style: TextStyle(
          color: Color(0xFF51495F),
          fontSize: 9,
          letterSpacing: 2.1,
        ),
      ),
    ],
  );
}

class _DevelopmentControls extends StatelessWidget {
  const _DevelopmentControls({required this.controller});

  final AiCoreController controller;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Color(0xED030307),
      border: Border(top: BorderSide(color: Color(0xFF17121E))),
    ),
    padding: const EdgeInsets.fromLTRB(28, 16, 28, 18),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 26,
      runSpacing: 12,
      children: [
        _ControlGroup(
          label: 'CORE STATE',
          child: Wrap(
            spacing: 6,
            children: AiCoreState.values
                .map(
                  (state) => _ControlButton(
                    label: state.name.toUpperCase(),
                    selected: controller.state == state,
                    onPressed: () => controller.setState(state),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        _ControlGroup(
          label: 'FIELD RESPONSE',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ControlButton(
                label: controller.mouseInteraction ? 'MOUSE ON' : 'MOUSE OFF',
                selected: controller.mouseInteraction,
                onPressed: () => controller.setMouseInteraction(
                  !controller.mouseInteraction,
                ),
              ),
              const SizedBox(width: 15),
              _CompactSlider(
                label: 'INTENSITY',
                value: controller.intensity,
                min: 0.55,
                max: 1.35,
                onChanged: controller.setIntensity,
              ),
              const SizedBox(width: 13),
              _CompactSlider(
                label: 'SPEECH',
                value: controller.speechIntensity,
                min: 0,
                max: 1,
                onChanged: controller.setSpeechIntensity,
              ),
            ],
          ),
        ),
        _ControlGroup(
          label: 'RENDER QUALITY',
          child: Wrap(
            spacing: 6,
            children: AiCoreQuality.values
                .map(
                  (quality) => _ControlButton(
                    label: quality.name.toUpperCase(),
                    selected: controller.quality == quality,
                    onPressed: () => controller.setQuality(quality),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    ),
  );
}

class _CompactSlider extends StatelessWidget {
  const _CompactSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF655D71),
          fontSize: 8,
          letterSpacing: 1.1,
        ),
      ),
      SizedBox(
        width: 88,
        child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 1,
            activeTrackColor: const Color(0xFF9650D4),
            inactiveTrackColor: const Color(0xFF24202B),
            thumbColor: const Color(0xFFDFC1FF),
            overlayColor: const Color(0x229650D4),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
          ),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ),
    ],
  );
}

class _ControlGroup extends StatelessWidget {
  const _ControlGroup({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF514A5B),
          fontSize: 8,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.8,
        ),
      ),
      const SizedBox(height: 8),
      child,
    ],
  );
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 29)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10),
      ),
      foregroundColor: WidgetStatePropertyAll(
        selected ? const Color(0xFFEADAFE) : const Color(0xFF6D6479),
      ),
      backgroundColor: WidgetStatePropertyAll(
        selected ? const Color(0xFF271631) : const Color(0xFF08080C),
      ),
      side: WidgetStatePropertyAll(
        BorderSide(
          color: selected ? const Color(0xFF7941A0) : const Color(0xFF201C25),
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1),
      ),
      overlayColor: const WidgetStatePropertyAll(Color(0x198D50AF)),
    ),
    child: Text(label),
  );
}

