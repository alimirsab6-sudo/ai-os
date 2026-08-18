import 'package:ai_os/browser/embedded/browser_controller.dart';
import 'package:ai_os/browser/embedded/cronyx_browser_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves the dedicated profile under Windows local app data', () {
    final result = CronyxBrowserProfile.resolvePath({
      'LOCALAPPDATA': r'C:\Users\Test\AppData\Local',
    });

    expect(
      result.fold((path) => path, (_) => null),
      r'C:\Users\Test\AppData\Local\CronyX\Browser\Profile',
    );
  });

  test('missing local app data returns a structured profile failure', () {
    final result = CronyxBrowserProfile.resolvePath(const {});

    expect(
      result.fold((_) => null, (failure) => failure.code),
      'browser_profile_location_unavailable',
    );
  });

  test('embedded browser URL policy accepts only safe absolute web URLs', () {
    expect(
      EmbeddedBrowserUrlPolicy.validate(
        Uri.parse('https://example.com/docs?q=1'),
      ).isSuccess,
      isTrue,
    );
    expect(
      EmbeddedBrowserUrlPolicy.validate(
        Uri.parse('http://example.com'),
      ).isSuccess,
      isTrue,
    );
    for (final value in const [
      'file:///C:/secret.txt',
      'javascript:alert(1)',
      'data:text/plain,secret',
      'ftp://example.com',
      'https://user:password@example.com',
      'relative/path',
    ]) {
      final result = EmbeddedBrowserUrlPolicy.validate(Uri.parse(value));
      expect(result.isFailure, isTrue, reason: value);
      expect(
        result.fold((_) => null, (failure) => failure.code),
        'invalid_url',
      );
    }
  });
}
