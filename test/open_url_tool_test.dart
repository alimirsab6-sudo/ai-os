import 'package:ai_os/browser/browser_url_launcher.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/result.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/browser/open_url_tool.dart';
import 'package:ai_os/tools/tool.dart';
import 'package:flutter_test/flutter_test.dart';

final class _MockUrlLauncher implements BrowserUrlLauncher {
  Uri? launchedUrl;

  @override
  Future<Result<BrowserUrlLaunchReceipt>> launch(Uri url) async {
    launchedUrl = url;
    return Result.success(
      BrowserUrlLaunchReceipt(host: url.host, processId: 7),
    );
  }
}

void main() {
  test('opens a validated URL through the approved launcher', () async {
    final events = EventBus();
    final launcher = _MockUrlLauncher();
    final tool = OpenUrlTool(launcher: launcher, events: events);

    final result = await tool.execute(
      const {'url': 'https://example.com/path?q=1'},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.execute}),
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(launcher.launchedUrl?.host, 'example.com');
    await events.close();
  });

  test('accepts HTTP and emits ordered lifecycle events', () async {
    final events = EventBus();
    final eventTypes = <String>[];
    final subscription = events.events.listen(
      (event) => eventTypes.add(event.type),
    );
    final launcher = _MockUrlLauncher();
    final tool = OpenUrlTool(launcher: launcher, events: events);

    final result = await tool.execute(
      const {'url': 'http://example.com'},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.execute}),
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(eventTypes, [
      'tool.started',
      'tool.succeeded',
      'browser.url.opened',
    ]);
    await subscription.cancel();
    await events.close();
  });

  test('rejects unsafe schemes before launch', () async {
    final events = EventBus();
    final launcher = _MockUrlLauncher();
    final tool = OpenUrlTool(launcher: launcher, events: events);

    final result = await tool.execute(
      const {'url': 'file:///C:/Windows/System32/cmd.exe'},
      ToolExecutionContext(
        authorizer: AllowListPermissionAuthorizer({Permission.execute}),
      ),
    );

    expect(result.isFailure, isTrue);
    expect(result.fold((_) => null, (failure) => failure.code), 'invalid_url');
    expect(launcher.launchedUrl, isNull);
    await events.close();
  });

  test('permission denial prevents URL launch', () async {
    final events = EventBus();
    final launcher = _MockUrlLauncher();
    final tool = OpenUrlTool(launcher: launcher, events: events);

    final result = await tool.execute(const {
      'url': 'https://example.com',
    }, ToolExecutionContext(authorizer: AllowListPermissionAuthorizer({})));

    expect(result.isFailure, isTrue);
    expect(launcher.launchedUrl, isNull);
    await events.close();
  });
}

