import '../core/result.dart';

final class BrowserUrlLaunchReceipt {
  const BrowserUrlLaunchReceipt({required this.host, this.processId});

  final String host;
  final int? processId;
}

abstract interface class BrowserUrlLauncher {
  Future<Result<BrowserUrlLaunchReceipt>> launch(Uri url);
}
