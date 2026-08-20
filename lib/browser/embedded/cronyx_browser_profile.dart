import '../../core/result.dart';

final class CronyxBrowserProfile {
  const CronyxBrowserProfile._();

  static Result<String> resolvePath(Map<String, String> environment) {
    final localAppData = environment['LOCALAPPDATA']?.trim();
    if (localAppData == null || localAppData.isEmpty) {
      return const Result.failure(
        Failure(
          'The Windows local application-data location is unavailable.',
          code: 'browser_profile_location_unavailable',
        ),
      );
    }
    return Result.success('$localAppData\\CronyX\\Browser\\Profile');
  }
}

