import 'package:ai_os/browser/embedded/browser_controller.dart';
import 'package:ai_os/ui/browser/cronyx_browser_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/embedded_browser_fakes.dart';

const _palette = CronyxBrowserPalette(
  background: Color(0xFF030507),
  panel: Color(0xFF080C12),
  border: Color(0x2478AADC),
  borderStrong: Color(0x666EBEFF),
  primary: Color(0xFFE9F4FF),
  secondary: Color(0xFF9BAFBD),
  muted: Color(0xFF536576),
  accent: Color(0xFF4FB8FF),
  error: Color(0xFFFF687A),
);

void main() {
  testWidgets('workspace renders controller-backed browser state', (
    tester,
  ) async {
    final controller = FakeBrowserController();
    await controller.initialize();
    controller.emit(
      BrowserControllerState(
        isInitialized: true,
        loadingState: BrowserLoadingState.completed,
        currentUrl: Uri.parse('https://example.com'),
        title: 'Example Domain',
        canGoBack: true,
        canGoForward: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 900,
          height: 700,
          child: CronyxBrowserWorkspace(
            controller: controller,
            surfaceBuilder: (_, _) => const ColoredBox(
              key: Key('fake-browser-surface'),
              color: Colors.black,
            ),
            palette: _palette,
            onNavigate: (_) async {},
            onBack: () async {},
            onForward: () async {},
            onReload: () async {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('browser-workspace')), findsOneWidget);
    expect(find.byKey(const Key('fake-browser-surface')), findsOneWidget);
    expect(find.text('Example Domain'), findsOneWidget);
    expect(find.byKey(const Key('browser-back')), findsOneWidget);
    expect(find.byKey(const Key('browser-forward')), findsOneWidget);
    expect(find.byKey(const Key('browser-reload')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await controller.dispose();
    await controller.close();
  });

  testWidgets('address input validates and delegates safe navigation', (
    tester,
  ) async {
    final controller = FakeBrowserController();
    await controller.initialize();
    Uri? navigated;
    await tester.pumpWidget(
      MaterialApp(
        home: CronyxBrowserWorkspace(
          controller: controller,
          surfaceBuilder: (_, _) => const SizedBox.expand(),
          palette: _palette,
          onNavigate: (url) async => navigated = url,
          onBack: () async {},
          onForward: () async {},
          onReload: () async {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('browser-address-input')),
      'javascript:alert(1)',
    );
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(navigated, isNull);
    expect(find.text('Enter an absolute HTTP or HTTPS URL'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('browser-address-input')),
      'https://flutter.dev',
    );
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(navigated, Uri.parse('https://flutter.dev'));
    await controller.dispose();
    await controller.close();
  });
}
