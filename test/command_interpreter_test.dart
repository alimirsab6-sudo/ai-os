import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const interpreter = DeterministicCommandInterpreter();

  test('selects allow-listed application commands deterministically', () {
    const expectations = <String, String>{
      'Open Chrome': 'chrome',
      'Open Microsoft Edge': 'edge',
      'Open Notepad': 'notepad',
      'Open Calculator': 'calculator',
      'Open File Explorer': 'file_explorer',
      'Open Windows Settings': 'settings',
      'Open My PC': 'file_explorer',
      'Browse Files': 'file_explorer',
      'View Tasks': 'task_manager',
    };

    for (final entry in expectations.entries) {
      final result = interpreter.interpret(entry.key);
      expect(result.isSuccess, isTrue, reason: entry.key);
      expect(
        result.fold(
          (command) => (command as LaunchApplicationCommand).applicationId,
          (_) => null,
        ),
        entry.value,
      );
    }
  });

  test('selects only absolute HTTP and HTTPS URL commands', () {
    final result = interpreter.interpret('Open https://example.com/docs?q=1');

    expect(result.isSuccess, isTrue);
    expect(
      result.fold((command) => (command as OpenUrlCommand).url.host, (_) => ''),
      'example.com',
    );
    expect(
      interpreter.interpret('Open file:///C:/secret.txt').isFailure,
      isTrue,
    );
    expect(interpreter.interpret('Open javascript:alert(1)').isFailure, isTrue);
  });

  test('never treats unknown text as a terminal command', () {
    final result = interpreter.interpret('Run Command');

    expect(result.isFailure, isTrue);
    expect(
      result.fold((_) => null, (failure) => failure.code),
      'unsupported_command',
    );
  });
}
