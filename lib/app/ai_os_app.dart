import 'package:flutter/material.dart';

import '../core/orchestrator/orchestrator.dart';

class AiOsApp extends StatelessWidget {
  const AiOsApp({required this.orchestrator, super.key});

  final Orchestrator orchestrator;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI OS',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
    home: const ArchitecturePlaceholderPage(),
  );
}

/// Temporary shell only; product naming and interactive UI remain undecided.
class ArchitecturePlaceholderPage extends StatelessWidget {
  const ArchitecturePlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Core architecture foundation')));
}
