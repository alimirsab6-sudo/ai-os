import 'dart:io';

/// Locates the application-owned local model runtime without scanning the
/// filesystem or relying solely on the process working directory.
String resolveLocalRuntimeRoot({
  String? executablePath,
  String? workingDirectory,
}) {
  final candidates = <String>[];

  void addAncestors(String path) {
    var directory = Directory(path).absolute;
    for (var depth = 0; depth < 8; depth++) {
      if (!candidates.any(
        (candidate) => candidate.toLowerCase() == directory.path.toLowerCase(),
      )) {
        candidates.add(directory.path);
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
  }

  final resolvedExecutable = executablePath ?? Platform.resolvedExecutable;
  addAncestors(File(resolvedExecutable).parent.path);
  final currentDirectory = workingDirectory ?? Directory.current.path;
  addAncestors(currentDirectory);

  for (final candidate in candidates) {
    if (_containsLocalRuntime(candidate)) return candidate;
  }

  // Preserve structured runtime-unavailable failures when no valid runtime is
  // present instead of guessing or searching arbitrary locations.
  return Directory(currentDirectory).absolute.path;
}

bool _containsLocalRuntime(String root) {
  final separator = Platform.pathSeparator;
  return File(
        '$root${separator}runtime${separator}voice${separator}config'
        '${separator}keywords.txt',
      ).existsSync() &&
      File(
        '$root${separator}runtime${separator}kokoro${separator}model'
        '${separator}model_quantized.onnx',
      ).existsSync() &&
      File(
        '$root${separator}runtime${separator}kokoro${separator}voices'
        '${separator}af_bella.bin',
      ).existsSync();
}
