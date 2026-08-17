import 'package:flutter/material.dart';

import '../core/orchestrator/orchestrator.dart';
import '../ui/shell/cronyx_os_shell.dart';

class AiOsApp extends StatelessWidget {
  const AiOsApp({required this.orchestrator, super.key});

  final Orchestrator orchestrator;

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
    home: CronyxOsShell(orchestrator: orchestrator),
  );
}
