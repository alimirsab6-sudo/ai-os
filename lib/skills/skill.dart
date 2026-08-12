import '../core/result.dart';

final class SkillRequest {
  const SkillRequest({this.input = const {}});

  final Map<String, Object?> input;
}

final class SkillOutput {
  const SkillOutput({required this.message, this.data = const {}});

  final String message;
  final Map<String, Object?> data;
}

abstract interface class Skill {
  String get id;
  String get name;
  String get description;
  String? get trigger;

  Future<Result<SkillOutput>> execute(SkillRequest request);
}

final class PlaceholderSkill implements Skill {
  const PlaceholderSkill();

  @override
  String get id => 'skill.placeholder';

  @override
  String get name => 'Placeholder skill';

  @override
  String get description => 'Demonstrates the reusable workflow boundary.';

  @override
  String? get trigger => null;

  @override
  Future<Result<SkillOutput>> execute(SkillRequest request) async =>
      const Result.success(
        SkillOutput(message: 'Placeholder workflow completed.'),
      );
}
