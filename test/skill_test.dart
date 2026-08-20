import 'package:ai_os/skills/skill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'placeholder skill exposes metadata and an execution entry point',
    () async {
      const skill = PlaceholderSkill();

      expect(skill.id, 'skill.placeholder');
      expect(skill.trigger, isNull);
      final result = await skill.execute(const SkillRequest());
      expect(
        result.fold((value) => value.message, (_) => null),
        contains('completed'),
      );
    },
  );
}

