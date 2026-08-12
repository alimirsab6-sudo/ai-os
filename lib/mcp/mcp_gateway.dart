import '../core/result.dart';
import '../tools/tool.dart';

/// Boundary through which future MCP servers can contribute tools.
abstract interface class McpGateway {
  Future<Result<List<Tool>>> discoverTools();
}

/// Offline implementation used until MCP connectivity is introduced.
final class DisabledMcpGateway implements McpGateway {
  const DisabledMcpGateway();

  @override
  Future<Result<List<Tool>>> discoverTools() async =>
      const Result.success(<Tool>[]);
}
