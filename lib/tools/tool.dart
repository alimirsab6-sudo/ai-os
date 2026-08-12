import '../core/result.dart';
import '../core/security/permission.dart';

enum ToolValueType { string, number, boolean, object, array }

final class ToolInputField {
  const ToolInputField({
    required this.type,
    required this.description,
    this.required = false,
  });

  final ToolValueType type;
  final String description;
  final bool required;
}

final class ToolInputSchema {
  const ToolInputSchema({this.fields = const {}});

  final Map<String, ToolInputField> fields;
}

final class ToolExecutionContext {
  const ToolExecutionContext({required this.authorizer});

  final PermissionAuthorizer authorizer;
}

final class ToolOutput {
  const ToolOutput({required this.data, this.summary});

  final Map<String, Object?> data;
  final String? summary;
}

abstract interface class Tool {
  String get id;
  String get name;
  String get description;
  ToolInputSchema get inputSchema;
  Set<Permission> get requiredPermissions;

  Future<Result<ToolOutput>> execute(
    Map<String, Object?> input,
    ToolExecutionContext context,
  );
}

/// Enforces authorization before a concrete tool implementation is invoked.
abstract base class AuthorizedTool implements Tool {
  const AuthorizedTool();

  @override
  Future<Result<ToolOutput>> execute(
    Map<String, Object?> input,
    ToolExecutionContext context,
  ) async {
    final authorization = context.authorizer.authorize(
      PermissionRequest(
        subjectId: id,
        permissions: requiredPermissions,
        reason: description,
      ),
    );
    if (authorization case Failed<void>(:final failure)) {
      return Result.failure(failure);
    }
    return perform(input);
  }

  Future<Result<ToolOutput>> perform(Map<String, Object?> input);
}
