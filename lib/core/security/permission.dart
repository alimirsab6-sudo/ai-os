import '../result.dart';

enum Permission { read, write, execute, sensitive }

final class PermissionRequest {
  const PermissionRequest({
    required this.subjectId,
    required this.permissions,
    this.reason,
  });

  final String subjectId;
  final Set<Permission> permissions;
  final String? reason;
}

abstract interface class PermissionAuthorizer {
  Result<void> authorize(PermissionRequest request);
}

/// Local allow-list policy. An empty allow-list denies all permissions.
final class AllowListPermissionAuthorizer implements PermissionAuthorizer {
  AllowListPermissionAuthorizer(Set<Permission> allowed)
    : _allowed = Set.unmodifiable(allowed);

  final Set<Permission> _allowed;

  Set<Permission> get allowed => _allowed;

  @override
  Result<void> authorize(PermissionRequest request) {
    final denied = request.permissions.difference(_allowed);
    if (denied.isNotEmpty) {
      return Result.failure(
        Failure(
          'Permission denied for ${request.subjectId}: '
          '${denied.map((permission) => permission.name).join(', ')}.',
          code: 'permission_denied',
        ),
      );
    }
    return const Result.success(null);
  }
}

