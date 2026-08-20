import '../../browser/browser_url_launcher.dart';
import '../../core/events/app_event.dart';
import '../../core/events/event_bus.dart';
import '../../core/result.dart';
import '../../core/security/permission.dart';
import '../tool.dart';

final class OpenUrlTool extends AuthorizedTool {
  const OpenUrlTool({required this.launcher, required this.events});

  final BrowserUrlLauncher launcher;
  final EventPublisher events;

  @override
  String get id => 'browser.open_url';

  @override
  String get name => 'Open web address';

  @override
  String get description =>
      'Opens one validated HTTP or HTTPS address in an approved browser.';

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema(
    fields: {
      'url': ToolInputField(
        type: ToolValueType.string,
        description: 'An absolute HTTP or HTTPS URL.',
        required: true,
      ),
    },
  );

  @override
  Set<Permission> get requiredPermissions => const {Permission.execute};

  @override
  Future<Result<Map<String, Object?>>> prepare(
    Map<String, Object?> input,
  ) async {
    final rawUrl = input['url'];
    if (rawUrl is! String) return _invalidUrl();
    final url = Uri.tryParse(rawUrl.trim());
    if (url == null ||
        (url.scheme != 'http' && url.scheme != 'https') ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty) {
      return _invalidUrl();
    }
    return Result.success({'url': url});
  }

  @override
  Future<Result<ToolOutput>> perform(Map<String, Object?> input) async {
    final url = input['url'];
    if (url is! Uri) {
      return _invalidToolState();
    }
    final result = await launcher.launch(url);
    return result.fold(
      (receipt) => Result.success(
        ToolOutput(
          data: {'host': receipt.host, 'process_id': receipt.processId},
          summary: '${receipt.host} opened successfully.',
        ),
      ),
      Result.failure,
    );
  }

  @override
  void onStarted(Map<String, Object?> input) {
    final rawUrl = input['url'];
    final host = rawUrl is String ? Uri.tryParse(rawUrl)?.host : null;
    events.publish(
      ApplicationEvent(
        type: 'tool.started',
        occurredAt: DateTime.now().toUtc(),
        data: {'tool_id': id, 'host': ?host},
      ),
    );
  }

  @override
  void onSucceeded(ToolOutput output) {
    final occurredAt = DateTime.now().toUtc();
    events.publish(
      ApplicationEvent(
        type: 'tool.succeeded',
        occurredAt: occurredAt,
        data: {'tool_id': id, ...output.data},
      ),
    );
    events.publish(
      ApplicationEvent(
        type: 'browser.url.opened',
        occurredAt: occurredAt,
        data: {'host': output.data['host']},
      ),
    );
  }

  @override
  void onFailed(Failure failure) {
    events.publish(
      ApplicationEvent(
        type: 'tool.failed',
        occurredAt: DateTime.now().toUtc(),
        data: {'tool_id': id, 'failure_code': failure.code},
      ),
    );
  }

  Result<Map<String, Object?>> _invalidUrl() => const Result.failure(
    Failure(
      'Only an absolute HTTP or HTTPS web address can be opened.',
      code: 'invalid_url',
    ),
  );

  Result<ToolOutput> _invalidToolState() => const Result.failure(
    Failure('Validated URL is missing.', code: 'invalid_tool_state'),
  );
}

