import '../placeholder_tool.dart';

final class TerminalToolPlaceholder extends PlaceholderTool {
  const TerminalToolPlaceholder();

  @override
  String get id => 'terminal.placeholder';

  @override
  String get name => 'Terminal tools';

  @override
  String get description => 'Reserved boundary for future terminal execution.';
}

