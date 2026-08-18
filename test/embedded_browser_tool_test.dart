import 'package:ai_os/core/events/app_event.dart';
import 'package:ai_os/browser/embedded/browser_controller.dart';
import 'package:ai_os/core/events/event_bus.dart';
import 'package:ai_os/core/security/permission.dart';
import 'package:ai_os/tools/browser/embedded_browser_tool.dart';
import 'package:ai_os/tools/tool.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/embedded_browser_fakes.dart';

void main() {
  late EventBus events;
  late FakeBrowserController controller;
  late EmbeddedBrowserTool tool;

  setUp(() {
    events = EventBus();
    controller = FakeBrowserController();
    tool = EmbeddedBrowserTool(controller: controller, events: events);
  });

  tearDown(() async {
    await controller.dispose();
    await controller.close();
    await events.close();
  });

  ToolExecutionContext context({bool allowed = true}) => ToolExecutionContext(
    authorizer: AllowListPermissionAuthorizer(
      allowed ? {Permission.execute} : {},
    ),
  );

  test('initializes browser and emits created and ready lifecycle', () async {
    final types = <String>[];
    final subscription = events.events.listen((event) => types.add(event.type));

    final result = await tool.execute(const {
      'operation': 'initialize',
    }, context());

    expect(result.isSuccess, isTrue);
    expect(controller.operations, ['initialize']);
    expect(types, [
      'tool.started',
      'browser.created',
      'browser.ready',
      'tool.succeeded',
    ]);
    await subscription.cancel();
  });

  test('validates URL before navigation', () async {
    for (final value in const [
      'file:///C:/secret.txt',
      'javascript:alert(1)',
      'https://user:password@example.com',
    ]) {
      final result = await tool.execute({
        'operation': 'navigate',
        'url': value,
      }, context());
      expect(result.isFailure, isTrue, reason: value);
    }
    expect(controller.operations, isEmpty);
  });

  test('permission denial prevents initialization and navigation', () async {
    final result = await tool.execute(const {
      'operation': 'navigate',
      'url': 'https://example.com',
    }, context(allowed: false));

    expect(result.isFailure, isTrue);
    expect(controller.operations, isEmpty);
  });

  test(
    'navigation emits sanitized lifecycle through page completion',
    () async {
      final captured = <ApplicationEvent>[];
      final subscription = events.events.listen((event) {
        if (event is ApplicationEvent) captured.add(event);
      });

      final result = await tool.execute(const {
        'operation': 'navigate',
        'url': 'https://example.com/private?token=secret',
      }, context());
      controller.completeNavigation(title: 'Example Domain');

      expect(result.isSuccess, isTrue);
      expect(
        captured.map((event) => event.type),
        containsAllInOrder([
          'browser.navigation.requested',
          'browser.created',
          'browser.ready',
          'browser.navigation.started',
          'browser.navigation.completed',
          'browser.page.loaded',
        ]),
      );
      final serialized = captured.map((event) => event.data.toString()).join();
      expect(serialized, isNot(contains('token=secret')));
      expect(serialized, isNot(contains('Example Domain')));
      await subscription.cancel();
    },
  );

  test('supports back forward reload and browser disposal', () async {
    await tool.execute(const {'operation': 'initialize'}, context());
    controller.emit(
      BrowserControllerState(
        isInitialized: true,
        loadingState: BrowserLoadingState.completed,
        currentUrl: Uri.parse('https://example.com'),
        canGoBack: true,
        canGoForward: true,
      ),
    );
    for (final operation in const ['back', 'forward', 'reload']) {
      final result = await tool.execute({'operation': operation}, context());
      expect(result.isSuccess, isTrue);
      controller.completeNavigation();
    }
    final disposed = await tool.execute(const {
      'operation': 'dispose',
    }, context());

    expect(disposed.isSuccess, isTrue);
    expect(controller.operations, [
      'initialize',
      'back',
      'forward',
      'reload',
      'dispose',
    ]);
  });

  test(
    'disposal releases the session and permits clean reinitialization',
    () async {
      final types = <String>[];
      final subscription = events.events.listen(
        (event) => types.add(event.type),
      );

      await tool.execute(const {'operation': 'initialize'}, context());
      await tool.execute(const {'operation': 'dispose'}, context());
      final restarted = await tool.execute(const {
        'operation': 'initialize',
      }, context());

      expect(restarted.isSuccess, isTrue);
      expect(controller.operations, ['initialize', 'dispose', 'initialize']);
      expect(types.where((type) => type == 'browser.created'), hasLength(2));
      expect(types.where((type) => type == 'browser.ready'), hasLength(2));
      expect(types.where((type) => type == 'browser.disposed'), hasLength(1));
      await subscription.cancel();
    },
  );

  test(
    'controller navigation failure emits structured failure event',
    () async {
      controller.failNavigation = true;
      final types = <String>[];
      final subscription = events.events.listen(
        (event) => types.add(event.type),
      );

      final result = await tool.execute(const {
        'operation': 'navigate',
        'url': 'https://example.com',
      }, context());

      expect(result.isFailure, isTrue);
      expect(types, contains('browser.navigation.failed'));
      expect(types, isNot(contains('browser.navigation.completed')));
      await subscription.cancel();
    },
  );
}
