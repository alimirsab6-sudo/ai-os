import '../../core/events/app_event.dart';
import '../../core/events/event_bus.dart';
import '../../core/result.dart';
import '../../core/security/permission.dart';
import '../tool.dart';
import 'applications/application_descriptor.dart';
import 'applications/application_launcher.dart';
import 'applications/application_registry.dart';

final class LaunchApplicationTool extends AuthorizedTool {
  const LaunchApplicationTool({
    required this.registry,
    required this.launcher,
    required this.events,
  });

  final ApplicationRegistry registry;
  final ApplicationLauncher launcher;
  final EventPublisher events;

  @override
  String get id => 'windows.launch_application';

  @override
  String get name => 'Launch application';

  @override
  String get description =>
      'Launches an allow-listed application by its stable ID.';

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema(
    fields: {
      'application_id': ToolInputField(
        type: ToolValueType.string,
        description: 'Stable ID of a registered application.',
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
    final applicationId = input['application_id'];
    if (applicationId is! String || applicationId.trim().isEmpty) {
      return const Result.failure(
        Failure(
          '"application_id" must be a non-empty string.',
          code: 'invalid_tool_input',
        ),
      );
    }

    final resolved = registry.resolve(applicationId);
    if (resolved case Failed<ResolvedApplication>(:final failure)) {
      return Result.failure(failure);
    }
    return Result.success({
      'application': (resolved as Success<ResolvedApplication>).value,
    });
  }

  @override
  Future<Result<ToolOutput>> perform(Map<String, Object?> input) async {
    final application = input['application'];
    if (application is! ResolvedApplication) {
      return const Result.failure(
        Failure('Resolved application is missing.', code: 'invalid_tool_state'),
      );
    }
    final launchResult = await launcher.launch(application);
    return launchResult.fold(
      (receipt) => Result.success(
        ToolOutput(
          data: {
            'application_id': receipt.applicationId,
            'process_id': receipt.processId,
          },
          summary: 'Application launched.',
        ),
      ),
      Result.failure,
    );
  }

  @override
  void onStarted(Map<String, Object?> input) {
    events.publish(
      ApplicationEvent(
        type: 'tool.started',
        occurredAt: DateTime.now().toUtc(),
        data: {'tool_id': id, 'application_id': input['application_id']},
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
        type: 'application.launched',
        occurredAt: occurredAt,
        data: output.data,
      ),
    );
  }

  @override
  void onFailed(Failure failure) {
    events.publish(
      ApplicationEvent(
        type: 'tool.failed',
        occurredAt: DateTime.now().toUtc(),
        data: {
          'tool_id': id,
          'failure_code': failure.code,
          'message': failure.message,
        },
      ),
    );
  }
}
