import '../../core/events/app_event.dart';
import '../../core/events/event_bus.dart';
import '../../core/result.dart';
import '../../core/security/permission.dart';
import '../../tools/tool.dart';
import '../browser_session.dart';
import 'chrome_launcher.dart';
import 'chrome_profile_registry.dart';

final class DiscoverChromeProfilesTool extends AuthorizedTool {
  const DiscoverChromeProfilesTool({
    required this.registry,
    required this.events,
  });

  final ChromeProfileRegistry registry;
  final EventPublisher events;

  @override
  String get id => 'browser.chrome.discover_profiles';
  @override
  String get name => 'Discover Chrome profiles';
  @override
  String get description => 'Discovers local Chrome profiles for this user.';
  @override
  ToolInputSchema get inputSchema => const ToolInputSchema();
  @override
  Set<Permission> get requiredPermissions => const {Permission.read};

  @override
  Future<Result<ToolOutput>> perform(Map<String, Object?> input) async {
    final result = await registry.discoverProfiles();
    return result.fold(
      (profiles) => Result.success(
        ToolOutput(
          data: {
            'profiles': profiles.map((profile) => profile.toMap()).toList(),
            'profile_count': profiles.length,
          },
          summary: 'Chrome profiles discovered.',
        ),
      ),
      Result.failure,
    );
  }

  @override
  void onStarted(Map<String, Object?> input) => _publish('started');
  @override
  void onSucceeded(ToolOutput output) => _publish(
    'succeeded',
    data: {'success': true, 'profile_count': output.data['profile_count']},
  );
  @override
  void onFailed(Failure failure) => _publish(
    'failed',
    data: {'success': false, 'failure_code': failure.code},
  );

  void _publish(String phase, {Map<String, Object?> data = const {}}) {
    events.publish(
      ApplicationEvent(
        type: 'chrome.profile.discovery.$phase',
        occurredAt: DateTime.now().toUtc(),
        data: data,
      ),
    );
  }
}

final class LaunchChromeProfileTool extends AuthorizedTool {
  const LaunchChromeProfileTool({
    required this.launcher,
    required this.session,
    required this.events,
  });

  final ChromeLauncher launcher;
  final BrowserSession session;
  final EventPublisher events;

  @override
  String get id => 'browser.chrome.launch_profile';
  @override
  String get name => 'Launch Chrome profile';
  @override
  String get description =>
      'Launches Chrome with a validated discovered profile.';
  @override
  ToolInputSchema get inputSchema => const ToolInputSchema(
    fields: {
      'profile_id': ToolInputField(
        type: ToolValueType.string,
        description: 'Opaque Chrome profile ID returned by discovery.',
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
    final profileId = input['profile_id'];
    if (profileId is! String ||
        !RegExp(r'^chrome_profile_[0-9a-f]{16}$').hasMatch(profileId)) {
      return const Result.failure(
        Failure('Invalid Chrome profile ID.', code: 'invalid_profile_id'),
      );
    }
    return Result.success({'profile_id': profileId});
  }

  @override
  Future<Result<ToolOutput>> perform(Map<String, Object?> input) async {
    final result = await launcher.launch(input['profile_id']! as String);
    return result.fold((receipt) {
      final selected = session.selectProfile(receipt.profile);
      if (selected case Failed<void>(:final failure)) {
        return Result.failure(failure);
      }
      return Result.success(
        ToolOutput(
          data: {
            'profile_id': receipt.profile.id,
            'display_name': receipt.profile.displayName,
            'process_id': receipt.processId,
          },
          summary: 'Chrome profile launched.',
        ),
      );
    }, Result.failure);
  }

  @override
  void onStarted(Map<String, Object?> input) =>
      _publish('started', data: {'profile_id': input['profile_id']});
  @override
  void onSucceeded(ToolOutput output) => _publish(
    'succeeded',
    data: {
      'profile_id': output.data['profile_id'],
      'display_name': output.data['display_name'],
      'success': true,
    },
  );
  @override
  void onFailedWithInput(Failure failure, Map<String, Object?> input) =>
      _publish(
        'failed',
        data: {
          'profile_id': input['profile_id'],
          'success': false,
          'failure_code': failure.code,
        },
      );

  void _publish(String phase, {Map<String, Object?> data = const {}}) {
    events.publish(
      ApplicationEvent(
        type: 'chrome.profile.launch.$phase',
        occurredAt: DateTime.now().toUtc(),
        data: data,
      ),
    );
  }
}

