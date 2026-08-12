import '../core/result.dart';
import '../core/security/permission.dart';
import 'tool.dart';

abstract base class PlaceholderTool extends AuthorizedTool {
  const PlaceholderTool();

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema();

  @override
  Set<Permission> get requiredPermissions => const {Permission.execute};

  @override
  Future<Result<ToolOutput>> perform(Map<String, Object?> input) async =>
      Result.failure(
        Failure(
          '$name is a Milestone 0B placeholder and performs no action.',
          code: 'not_implemented',
        ),
      );
}
