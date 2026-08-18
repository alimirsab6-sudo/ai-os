import 'dart:convert';
import 'dart:io';

import 'package:ai_os/core/result.dart';
import 'package:ai_os/voice/profile/local_owner_profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/voice_fakes.dart';

void main() {
  late Directory temporary;
  late LocalOwnerProfileRepository repository;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cronyx-profile-test-');
    repository = LocalOwnerProfileRepository(directory: () async => temporary);
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'profile save stores only identity metadata and speaker embedding',
    () async {
      final saved = await repository.save(ownerProfile());
      final file = File('${temporary.path}\\CronyX\\voice\\owner_profile.json');
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;

      expect(saved.isSuccess, isTrue);
      expect(json['display_name'], 'Ali');
      expect((json['embedding'] as List).length, 256);
      expect(json.containsKey('audio'), isFalse);
      expect(json.containsKey('transcript'), isFalse);
      expect(json.containsKey('recording'), isFalse);
    },
  );

  test('saved profile can be loaded and reset', () async {
    await repository.save(ownerProfile());

    final loaded = await repository.load();
    final reset = await repository.reset();
    final afterReset = await repository.load();

    expect((loaded as Success).value.displayName, 'Ali');
    expect(reset.isSuccess, isTrue);
    expect((afterReset as Success).value, isNull);
  });

  test(
    'corrupt profile is rejected instead of authenticating anyone',
    () async {
      final file = File('${temporary.path}\\CronyX\\voice\\owner_profile.json');
      await file.parent.create(recursive: true);
      await file.writeAsString('{"display_name":"Ali"}');

      final result = await repository.load();

      expect((result as Failed).failure.code, 'profile_invalid');
    },
  );
}
