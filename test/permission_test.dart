import 'package:ai_os/core/security/permission.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows only requests covered by the allow-list', () {
    final authorizer = AllowListPermissionAuthorizer({
      Permission.read,
      Permission.write,
    });

    expect(
      authorizer
          .authorize(
            const PermissionRequest(
              subjectId: 'test',
              permissions: {Permission.read},
            ),
          )
          .isSuccess,
      isTrue,
    );
    expect(
      authorizer
          .authorize(
            const PermissionRequest(
              subjectId: 'test',
              permissions: {Permission.execute},
            ),
          )
          .isFailure,
      isTrue,
    );
  });
}

