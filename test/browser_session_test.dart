import 'package:ai_os/browser/browser_session.dart';
import 'package:ai_os/browser/chrome/chrome_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chrome_fakes.dart';

void main() {
  test('stores the selected Chrome profile as browser session state', () {
    final session = BrowserSession();
    expect(session.selectProfile(testChromeProfile).isSuccess, isTrue);
    expect(session.selectedProfile, same(testChromeProfile));
    session.clear();
    expect(session.selectedProfile, isNull);
  });

  test('invalid profile state is rejected without changing session', () {
    final session = BrowserSession();
    const invalid = ChromeProfile(
      id: 'Profile 1',
      displayName: 'Bad',
      directoryIdentifier: 'Profile 1',
      isDefault: false,
    );
    expect(session.selectProfile(invalid).isFailure, isTrue);
    expect(session.selectedProfile, isNull);
  });
}
