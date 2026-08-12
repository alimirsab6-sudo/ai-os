import '../../../core/result.dart';
import 'application_descriptor.dart';

final class ApplicationLaunchReceipt {
  const ApplicationLaunchReceipt({
    required this.applicationId,
    required this.processId,
  });

  final String applicationId;
  final int processId;
}

abstract interface class ApplicationLauncher {
  Future<Result<ApplicationLaunchReceipt>> launch(
    ResolvedApplication application,
  );
}
