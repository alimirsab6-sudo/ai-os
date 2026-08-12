import '../../core/result.dart';
import '../../tools/tool.dart';
import '../agent.dart';

/// Declares the future PC-agent boundary without controlling the computer.
final class PcAgent implements Agent {
  PcAgent({List<Tool> tools = const []}) : _tools = List.unmodifiable(tools);

  final List<Tool> _tools;

  @override
  String get id => 'agent.pc';

  @override
  String get name => 'PC Agent';

  @override
  String get description => 'Future coordinator for authorized PC operations.';

  @override
  List<Tool> get availableTools => _tools;

  @override
  Future<Result<AgentResponse>> handle(AgentRequest request) async =>
      const Result.failure(
        Failure(
          'PC control is not implemented in Milestone 0B.',
          code: 'not_implemented',
        ),
      );
}
