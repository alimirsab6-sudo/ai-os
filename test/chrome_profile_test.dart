import 'package:ai_os/browser/chrome/chrome_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ChromeProfile exposes safe structured metadata', () {
    const profile = ChromeProfile(
      id: 'chrome_profile_0123456789abcdef',
      displayName: 'Personal',
      directoryIdentifier: 'Default',
      isDefault: true,
      avatarIcon: 'chrome://theme/IDR_PROFILE_AVATAR_0',
    );
    expect(profile.toMap(), {
      'profile_id': profile.id,
      'display_name': 'Personal',
      'directory_identifier': 'Default',
      'is_default': true,
      'avatar_icon': 'chrome://theme/IDR_PROFILE_AVATAR_0',
    });
    expect(profile.id, isNot(contains(r'\')));
  });
}
