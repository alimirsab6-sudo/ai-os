import 'package:ai_os/core/result.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/tool.dart';
import 'package:flutter_test/flutter_test.dart';

final class MockTool extends AuthorizedTool {
  @override
  String get id => 'test.echo';

  @override
  String get name => 'Echo';

  @override
  String get description => 'Returns its input.';

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema(
    fields: {
      'text': ToolInputField(
        type: ToolValueType.string,
        description: 'Text to echo.',
        required: true,
      ),
    },
  );

  @override
  Set<Permission> get requiredPermissions => const {Permission.execute};

  @override
  Future<Result<ToolOutput>> perform(Map<String, Object?> input) async =>
      Result.success(ToolOutput(data: input));
}

void main() {
  test('authorized mock tool returns structured output', () async {
    final result = await MockTool().execute(
      const {'text': 'hello'},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.execute}),
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(result.fold((value) => value.data['text'], (_) => null), 'hello');
  });

  test('mock tool is stopped at the security boundary', () async {
    final result = await MockTool().execute(const {
      'text': 'hello',
    }, ToolExecutionContext(authorizer: AllowListPermissionAuthorizer({})));

    expect(result.isFailure, isTrue);
  });
}

