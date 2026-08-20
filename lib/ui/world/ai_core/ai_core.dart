import 'package:flutter/widgets.dart';

import 'ai_core_controller.dart';
import 'ai_core_renderer.dart';

/// The reusable, visual-only central entity for the future spatial workspace.
class AiCore extends StatelessWidget {
  const AiCore({
    required this.controller,
    this.size,
    this.animationEnabled = true,
    this.particleDensity = 1,
    super.key,
  }) : assert(particleDensity > 0 && particleDensity <= 1);

  final AiCoreController controller;
  final double? size;
  final bool animationEnabled;
  final double particleDensity;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, child) => Semantics(
      label: 'Living AI Core ${controller.state.name}',
      child: size == null
          ? SizedBox.expand(child: child)
          : SizedBox.square(dimension: size, child: child),
    ),
    child: AiCoreRenderer(
      controller: controller,
      animationEnabled: animationEnabled,
      particleDensity: particleDensity,
    ),
  );
}

