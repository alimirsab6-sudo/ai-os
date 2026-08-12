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
    onStarted(input);
    final preparation = await prepare(input);
    if (preparation case Failed<Map<String, Object?>>(:final failure)) {
      onFailedWithInput(failure, input);
      return Result.failure(failure);
    }
    final authorization = context.authorizer.authorize(
      PermissionRequest(
        subjectId: id,
        permissions: requiredPermissions,
        reason: description,
      ),
    );
    if (authorization case Failed<void>(:final failure)) {
      onFailedWithInput(failure, input);
      return Result.failure(failure);
    }
    final preparedInput = (preparation as Success<Map<String, Object?>>).value;
    final result = await perform(preparedInput);
    result.fold(onSucceeded, (failure) => onFailedWithInput(failure, input));
    return result;
  }

  Future<Result<Map<String, Object?>>> prepare(
    Map<String, Object?> input,
  ) async => Result.success(input);

  Future<Result<ToolOutput>> perform(Map<String, Object?> input);

  void onStarted(Map<String, Object?> input) {}

  void onSucceeded(ToolOutput output) {}

  void onFailed(Failure failure) {}

  void onFailedWithInput(Failure failure, Map<String, Object?> input) =>
      onFailed(failure);
}
