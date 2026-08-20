import 'dart:convert';
import 'dart:io';

import '../../core/result.dart';
import 'chrome_installation_resolver.dart';
import 'chrome_profile.dart';
import 'chrome_profile_registry.dart';

typedef ProfileFileReader = Future<String> Function(String path);
typedef ProfilePathExists = bool Function(String path);

Future<String> _readProfileFile(String path) => File(path).readAsString();
bool _profilePathExists(String path) => Directory(path).existsSync();

final class WindowsChromeProfileRegistry implements ChromeProfileRegistry {
  WindowsChromeProfileRegistry({
    required this.installationResolver,
    Map<String, String>? environment,
    ProfileFileReader? readFile,
    ProfilePathExists? directoryExists,
    String? runtimeScope,
  }) : _environment = environment ?? Platform.environment,
       _readFile = readFile ?? _readProfileFile,
       _directoryExists = directoryExists ?? _profilePathExists,
       _runtimeScope =
           runtimeScope ??
           DateTime.now().microsecondsSinceEpoch.toRadixString(16);

  final ChromeInstallationResolver installationResolver;
  final Map<String, String> _environment;
  final ProfileFileReader _readFile;
  final ProfilePathExists _directoryExists;
  final String _runtimeScope;
  final Map<String, ResolvedChromeProfile> _profiles = {};

  @override
  Future<Result<List<ChromeProfile>>> discoverProfiles() async {
    final installation = installationResolver.resolve();
    if (installation case Failed(:final failure)) {
      _profiles.clear();
      return Result.failure(failure);
    }
    final localAppData = _environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.trim().isEmpty) {
      _profiles.clear();
      return const Result.failure(
        Failure(
          'The Windows local application-data location is unavailable.',
          code: 'chrome_profile_location_unavailable',
        ),
      );
    }
    final userData = '$localAppData\\Google\\Chrome\\User Data';
    final localState = '$userData\\Local State';
    try {
      final decoded = jsonDecode(await _readFile(localState));
      if (decoded is! Map<String, Object?>) {
        return _failAndClear(
          'Chrome profile metadata is malformed.',
          'malformed_chrome_metadata',
        );
      }
      final profile = decoded['profile'];
      final infoCache = profile is Map<String, Object?>
          ? profile['info_cache']
          : null;
      if (infoCache is! Map<String, Object?>) {
        return _failAndClear(
          'Chrome profile metadata is missing.',
          'chrome_profile_metadata_missing',
        );
      }
      final orderedDirectories = <String>[];
      final order = profile is Map<String, Object?>
          ? profile['profiles_order']
          : null;
      if (order is List) {
        orderedDirectories.addAll(order.whereType<String>());
      }
      final remaining =
          infoCache.keys
              .whereType<String>()
              .where((key) => !orderedDirectories.contains(key))
              .toList()
            ..sort();
      orderedDirectories.addAll(remaining);

      final discovered = <String, ResolvedChromeProfile>{};
      for (final directory in orderedDirectories) {
        if (!_isSafeDirectoryIdentifier(directory)) continue;
        final metadata = infoCache[directory];
        if (metadata is! Map<String, Object?>) continue;
        bool exists;
        try {
          exists = _directoryExists('$userData\\$directory');
        } on Object {
          continue;
        }
        if (!exists) continue;
        final name = metadata['name'];
        final displayName = name is String && name.trim().isNotEmpty
            ? name.trim()
            : directory;
        final id = 'chrome_profile_${_opaqueId(directory)}';
        final avatar = metadata['avatar_icon'];
        final resolved = ResolvedChromeProfile(
          profile: ChromeProfile(
            id: id,
            displayName: displayName,
            directoryIdentifier: directory,
            isDefault: directory == 'Default',
            avatarIcon: avatar is String && avatar.isNotEmpty ? avatar : null,
          ),
        );
        discovered[id] = resolved;
      }
      _profiles
        ..clear()
        ..addAll(discovered);
      return Result.success(listProfiles());
    } on FileSystemException {
      return _failAndClear(
        'Chrome profile metadata is unavailable or inaccessible.',
        'chrome_profile_metadata_unavailable',
      );
    } on FormatException {
      return _failAndClear(
        'Chrome profile metadata is malformed.',
        'malformed_chrome_metadata',
      );
    } on Object {
      return _failAndClear(
        'Chrome profile discovery failed.',
        'chrome_profile_discovery_failed',
      );
    }
  }

  @override
  Result<ChromeProfile> getProfile(String profileId) => resolveProfile(
    profileId,
  ).fold((resolved) => Result.success(resolved.profile), Result.failure);

  @override
  List<ChromeProfile> listProfiles() =>
      List.unmodifiable(_profiles.values.map((resolved) => resolved.profile));

  @override
  Result<ResolvedChromeProfile> resolveProfile(String profileId) {
    if (!RegExp(r'^chrome_profile_[0-9a-f]{16}$').hasMatch(profileId)) {
      return const Result.failure(
        Failure('Invalid Chrome profile ID.', code: 'invalid_profile_id'),
      );
    }
    final profile = _profiles[profileId];
    return profile == null
        ? const Result.failure(
            Failure(
              'The Chrome profile is unknown or stale.',
              code: 'unknown_chrome_profile',
            ),
          )
        : Result.success(profile);
  }

  Result<List<ChromeProfile>> _failAndClear(String message, String code) {
    _profiles.clear();
    return Result.failure(Failure(message, code: code));
  }

  String _opaqueId(String directory) {
    var hash = 0xcbf29ce484222325;
    for (final unit in '$_runtimeScope\u0000$directory'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

bool _isSafeDirectoryIdentifier(String value) =>
    value.isNotEmpty &&
    value.length <= 128 &&
    value != '.' &&
    value != '..' &&
    !value.contains(RegExp(r'[\\/:*?"<>|]'));

