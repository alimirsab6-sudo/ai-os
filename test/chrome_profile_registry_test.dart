import 'dart:io';

import 'package:ai_os/browser/chrome/windows_chrome_profile_registry.dart';
import 'package:ai_os/core/result.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chrome_fakes.dart';

const metadata = '''{
  "profile": {
    "profiles_order": ["Default", "Profile 1", "Profile 2"],
    "info_cache": {
      "Default": {"name": "Personal", "avatar_icon": "avatar-0"},
      "Profile 1": {"name": "Work"},
      "Profile 2": {"name": "Business"}
    }
  }
}''';

void main() {
  test(
    'discovers multiple profiles deterministically with opaque IDs',
    () async {
      final registry = _registry(metadata);
      final first = await registry.discoverProfiles();
      final second = await registry.discoverProfiles();
      final profiles = first.fold(
        (value) => value,
        (_) => throw StateError('failed'),
      );
      expect(profiles.map((profile) => profile.displayName), [
        'Personal',
        'Work',
        'Business',
      ]);
      expect(profiles.first.isDefault, isTrue);
      expect(
        profiles.every(
          (profile) =>
              RegExp(r'^chrome_profile_[0-9a-f]{16}$').hasMatch(profile.id),
        ),
        isTrue,
      );
      expect(
        second.fold((value) => value.map((p) => p.id), (_) => const []),
        profiles.map((p) => p.id),
      );
      expect(registry.listProfiles().length, 3);
      expect(registry.getProfile(profiles[1].id).isSuccess, isTrue);
    },
  );

  test('skips one malformed profile without failing valid profiles', () async {
    final malformedEntry = metadata.replaceFirst(
      '"Profile 1": {"name": "Work"}',
      '"Profile 1": "bad entry"',
    );
    final result = await _registry(malformedEntry).discoverProfiles();
    expect(
      result.fold(
        (profiles) => profiles.map((p) => p.displayName),
        (_) => const [],
      ),
      ['Personal', 'Business'],
    );
  });

  test(
    'falls back to directory identifier when profile name is missing',
    () async {
      final missingName = metadata.replaceFirst('{"name": "Work"}', '{}');
      final result = await _registry(missingName).discoverProfiles();
      expect(
        result.fold((profiles) => profiles[1].displayName, (_) => null),
        'Profile 1',
      );
    },
  );

  test('skips inaccessible profile directory', () async {
    final registry = _registry(
      metadata,
      directoryExists: (path) {
        if (path.endsWith('Profile 1')) {
          throw const FileSystemException('denied');
        }
        return true;
      },
    );
    final result = await registry.discoverProfiles();
    expect(
      result.fold(
        (profiles) => profiles.map((p) => p.displayName),
        (_) => const [],
      ),
      ['Personal', 'Business'],
    );
  });

  test('malformed and missing metadata return structured failures', () async {
    final malformed = await _registry('{bad').discoverProfiles();
    final missing = await _registry('{"profile":{}}').discoverProfiles();
    expect(_failureCode(malformed), 'malformed_chrome_metadata');
    expect(_failureCode(missing), 'chrome_profile_metadata_missing');
  });

  test('missing Chrome prevents profile metadata access', () async {
    var read = false;
    final registry = WindowsChromeProfileRegistry(
      installationResolver: MockChromeInstallationResolver(
        failure: const Failure('missing', code: 'chrome_not_installed'),
      ),
      environment: const {'LOCALAPPDATA': r'C:\Users\Test\AppData\Local'},
      readFile: (_) async {
        read = true;
        return metadata;
      },
      runtimeScope: 'test',
    );
    final result = await registry.discoverProfiles();
    expect(_failureCode(result), 'chrome_not_installed');
    expect(read, isFalse);
  });

  test('rejects unknown, malformed, and injected profile IDs', () async {
    final registry = _registry(metadata);
    await registry.discoverProfiles();
    expect(
      registry.getProfile('chrome_profile_ffffffffffffffff').isFailure,
      isTrue,
    );
    expect(registry.getProfile('Profile 1').isFailure, isTrue);
    expect(registry.getProfile(r'chrome_profile_..\evil').isFailure, isTrue);
  });
}

WindowsChromeProfileRegistry _registry(
  String source, {
  bool Function(String path)? directoryExists,
}) => WindowsChromeProfileRegistry(
  installationResolver: MockChromeInstallationResolver(),
  environment: const {'LOCALAPPDATA': r'C:\Users\Test\AppData\Local'},
  readFile: (_) async => source,
  directoryExists: directoryExists ?? (_) => true,
  runtimeScope: 'stable-test-scope',
);

String? _failureCode<T>(Result<T> result) =>
    result.fold((_) => null, (failure) => failure.code);

