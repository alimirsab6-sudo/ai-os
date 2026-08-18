import 'dart:io';

import 'package:ai_os/app/local_runtime_root.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'cronyx-runtime-root-',
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('finds the runtime from executable ancestors, independent of cwd', () {
    final project = Directory('${temporaryDirectory.path}\\project')
      ..createSync();
    _createRuntimeMarkers(project.path);
    final unrelated = Directory('${temporaryDirectory.path}\\unrelated')
      ..createSync();

    final result = resolveLocalRuntimeRoot(
      executablePath:
          '${project.path}\\build\\windows\\x64\\runner\\Release\\ai_os.exe',
      workingDirectory: unrelated.path,
    );

    expect(result, project.absolute.path);
  });

  test('falls back to a valid working-directory runtime for development', () {
    final project = Directory('${temporaryDirectory.path}\\project')
      ..createSync();
    _createRuntimeMarkers(project.path);

    final result = resolveLocalRuntimeRoot(
      executablePath: '${temporaryDirectory.path}\\sdk\\dart.exe',
      workingDirectory: project.path,
    );

    expect(result, project.absolute.path);
  });
}

void _createRuntimeMarkers(String root) {
  for (final path in [
    '$root\\runtime\\voice\\config\\keywords.txt',
    '$root\\runtime\\kokoro\\model\\model_quantized.onnx',
    '$root\\runtime\\kokoro\\voices\\af_bella.bin',
  ]) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync([1]);
  }
}
