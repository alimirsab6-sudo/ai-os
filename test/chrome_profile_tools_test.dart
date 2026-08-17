import 'package:ai_os/browser/browser_session.dart';
import 'package:ai_os/browser/chrome/chrome_profile_tools.dart';
import 'package:ai_os/core/events/app_event.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/tool.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chrome_fakes.dart';

void main() {
  test('discovery requires read permission and emits lifecycle', () async {
    final events = EventBus();
    final observed = <ApplicationEvent>[];
    final subscription = events.events.listen((event) {
      if (event is ApplicationEvent) observed.add(event);
    });
    final registry = MockChromeProfileRegistry();
    final tool = DiscoverChromeProfilesTool(registry: registry, events: events);
    final denied = await tool.execute(
      const {},
      ToolExecutionContext(authorizer: AllowListPermissionAuthorizer({})),
    );
    expect(denied.isFailure, isTrue);
    expect(registry.discoveryCount, 0);
    final allowed = await tool.execute(
      const {},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.read}),
      ),
    );
    expect(allowed.isSuccess, isTrue);
    expect(observed.map((event) => event.type), [
      'chrome.profile.discovery.started',
      'chrome.profile.discovery.failed',
      'chrome.profile.discovery.started',
      'chrome.profile.discovery.succeeded',
    ]);
    await subscription.cancel();
    await events.close();
  });

  test(
    'launch permission denial prevents launcher and session changes',
    () async {
      final events = EventBus();
      final launcher = MockChromeLauncher();
      final session = BrowserSession();
      final result =
          await LaunchChromeProfileTool(
            launcher: launcher,
            session: session,
            events: events,
          ).execute(
            const {'profile_id': 'chrome_profile_0123456789abcdef'},
            ToolExecutionContext(authorizer: AllowListPermissionAuthorizer({})),
          );
      expect(result.isFailure, isTrue);
      expect(launcher.launchCount, 0);
      expect(session.selectedProfile, isNull);
      await events.close();
    },
  );

  test(
    'successful launch updates session and emits path-free lifecycle',
    () async {
      final events = EventBus();
      final observed = <ApplicationEvent>[];
      final subscription = events.events.listen((event) {
        if (event is ApplicationEvent) observed.add(event);
      });
      final session = BrowserSession();
      final result =
          await LaunchChromeProfileTool(
            launcher: MockChromeLauncher(),
            session: session,
            events: events,
          ).execute(
            const {'profile_id': 'chrome_profile_0123456789abcdef'},
            ToolExecutionContext(
              authorizer: AllowListPermissionAuthorizer({Permission.execute}),
            ),
          );
      expect(result.isSuccess, isTrue);
      expect(session.selectedProfile?.displayName, 'Work');
      expect(observed.map((event) => event.type), [
        'chrome.profile.launch.started',
        'chrome.profile.launch.succeeded',
      ]);
      expect(observed.join(), isNot(contains(r'C:\')));
      await subscription.cancel();
      await events.close();
    },
  );

  test('invalid profile ID fails before authorization or launch', () async {
    final events = EventBus();
    final launcher = MockChromeLauncher();
    final result =
        await LaunchChromeProfileTool(
          launcher: launcher,
          session: BrowserSession(),
          events: events,
        ).execute(
          const {'profile_id': r'..\Default'},
          ToolExecutionContext(
            authorizer: AllowListPermissionAuthorizer({Permission.execute}),
          ),
        );
    expect(result.isFailure, isTrue);
    expect(launcher.launchCount, 0);
    await events.close();
  });
}
