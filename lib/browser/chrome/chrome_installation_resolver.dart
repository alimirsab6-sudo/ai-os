import '../../core/result.dart';

final class ResolvedChromeInstallation {
  const ResolvedChromeInstallation({required this.executablePath});

  final String executablePath;
}

abstract interface class ChromeInstallationResolver {
  Result<ResolvedChromeInstallation> resolve();
}

