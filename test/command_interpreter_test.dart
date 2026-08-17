import 'package:ai_os/core/orchestrator/orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const interpreter = DeterministicCommandInterpreter();

  test('selects allow-listed application commands deterministically', () {
    const expectations = <String, String>{
      'Open Chrome': 'chrome',
      'Launch Chrome': 'chrome',
      'Start Chrome': 'chrome',
      'please open chrome': 'chrome',
      'Open Microsoft Edge': 'edge',
      'Launch Microsoft Edge': 'edge',
      'Start Edge': 'edge',
      'Open Notepad': 'notepad',
      'Launch Notepad': 'notepad',
      'Start Notepad': 'notepad',
      'Open Calculator': 'calculator',
      'Launch Calc': 'calculator',
      'Start Calculator': 'calculator',
      'Open File Explorer': 'file_explorer',
      'Launch Explorer': 'file_explorer',
      'Open Windows Settings': 'settings',
      'Launch Settings': 'settings',
      'Open My PC': 'file_explorer',
      'Browse Files': 'file_explorer',
      'View Tasks': 'task_manager',
      'Open Task Manager': 'task_manager',
      'Launch Task Manager': 'task_manager',
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

  test('normalizes case, whitespace, punctuation, and polite prefixes', () {
    const commands = [
      '  OPEN    CHROME  ',
      'Please   launch   Microsoft Edge.',
      'Could you please open Notepad!',
      'can you please start calculator',
    ];
    const expectedIds = ['chrome', 'edge', 'notepad', 'calculator'];

    for (var index = 0; index < commands.length; index++) {
      final result = interpreter.interpret(commands[index]);
      expect(result.isSuccess, isTrue, reason: commands[index]);
      expect(
        result.fold(
          (command) => (command as LaunchApplicationCommand).applicationId,
          (_) => null,
        ),
        expectedIds[index],
      );
    }
  });

  test('selects only absolute HTTP and HTTPS URL commands', () {
    final httpsResult = interpreter.interpret(
      'Open https://example.com/docs?q=1',
    );
    final httpResult = interpreter.interpret('Go to http://example.com');

    expect(httpsResult.isSuccess, isTrue);
    expect(httpResult.isSuccess, isTrue);
    expect(
      httpsResult.fold(
        (command) => (command as OpenUrlCommand).url.host,
        (_) => '',
      ),
      'example.com',
    );
    expect(
      interpreter.interpret('Open file:///C:/secret.txt').isFailure,
      isTrue,
    );
    expect(interpreter.interpret('Open javascript:alert(1)').isFailure, isTrue);
    expect(interpreter.interpret('Open ftp://example.com').isFailure, isTrue);
    expect(
      interpreter.interpret('Open https://user@example.com').isFailure,
      isTrue,
    );
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
