import 'package:flutter/material.dart';

import 'app/ai_os_app.dart';
import 'app/composition_root.dart';
import 'core/orchestrator/orchestrator.dart';

void main() {
  final services = CompositionRoot.create();
  runApp(AiOsApp(orchestrator: services.get<Orchestrator>()));
}
