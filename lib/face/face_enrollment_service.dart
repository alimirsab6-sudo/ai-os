import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:face_detection_tflite/face_detection_tflite.dart';
import 'package:path_provider/path_provider.dart';

final class FaceEnrollmentService {
  FaceEnrollmentService({this._detector});

  FaceDetector? _detector;
  bool _running = false;

  static const double verificationThreshold = 0.78;

  Future<void> initialize() async {
    if (_detector != null && _detector!.isReady) return;

    _detector = FaceDetector();

    await _detector!.initialize(
      model: FaceDetectionModel.frontCamera,
      useCompiledModel: true,
      minFacePresenceConfidence: 0.5,
    );
  }

  Future<FaceEnrollmentResult> enroll(
    CameraController controller, {
    int requiredSamples = 3,
    void Function(int current, int total)? onProgress,
  }) async {
    await initialize();

    if (!controller.value.isInitialized) {
      return const FaceEnrollmentResult.failure(
        'Camera is not initialized.',
      );
    }

    if (_running) {
      return const FaceEnrollmentResult.failure(
        'Enrollment is already running.',
      );
    }

    _running = true;

    try {
      final embeddings = <List<double>>[];

      for (var sample = 0; sample < requiredSamples; sample++) {
        if (!controller.value.isInitialized) {
          return const FaceEnrollmentResult.failure(
            'Camera stopped during enrollment.',
          );
        }

        final picture = await controller.takePicture();
        final bytes = await picture.readAsBytes();

        final faces = await _detector!.detectFacesFromBytes(
          bytes,
          mode: FaceDetectionMode.full,
        );

        if (faces.length != 1) {
          return FaceEnrollmentResult.failure(
            faces.isEmpty
                ? 'No face detected. Look directly at the camera.'
                : 'Please make sure only one person is visible.',
          );
        }

        final face = faces.first;

        if (face.score < 0.60) {
          return const FaceEnrollmentResult.failure(
            'Face detection confidence is too low.',
          );
        }

        if (face.widthFraction < 0.15) {
          return const FaceEnrollmentResult.failure(
            'Move closer to the camera.',
          );
        }

        final embedding = await _detector!.getFaceEmbedding(
          face,
          bytes,
        );

        embeddings.add(
          embedding.map((value) => value.toDouble()).toList(),
        );

        onProgress?.call(sample + 1, requiredSamples);
      }

      if (embeddings.isEmpty) {
        return const FaceEnrollmentResult.failure(
          'No usable face samples were captured.',
        );
      }

      final length = embeddings.first.length;
      final average = List<double>.filled(length, 0);

      for (final embedding in embeddings) {
        if (embedding.length != length) {
          return const FaceEnrollmentResult.failure(
            'Face embedding dimensions did not match.',
          );
        }

        for (var index = 0; index < length; index++) {
          average[index] += embedding[index];
        }
      }

      for (var index = 0; index < average.length; index++) {
        average[index] /= embeddings.length;
      }

      await _saveIdentity(average);

      return FaceEnrollmentResult.success(average);
    } catch (error) {
      return FaceEnrollmentResult.failure(
        'Face enrollment failed: $error',
      );
    } finally {
      _running = false;
    }
  }

  Future<FaceVerificationResult> verify(
    CameraController controller,
    List<double> enrolledEmbedding, {
    int samples = 1,
    void Function(int current, int total)? onProgress,
  }) async {
    await initialize();

    if (!controller.value.isInitialized) {
      return const FaceVerificationResult.failure(
        'Camera is not initialized.',
      );
    }

    if (_running) {
      return const FaceVerificationResult.failure(
        'Face verification is already running.',
      );
    }

    _running = true;

    try {
      final embeddings = <List<double>>[];

      for (var sample = 0; sample < samples; sample++) {
        final picture = await controller.takePicture();
        final bytes = await picture.readAsBytes();

        final faces = await _detector!.detectFacesFromBytes(
          bytes,
          mode: FaceDetectionMode.full,
        );

        if (faces.length != 1) {
          return FaceVerificationResult.failure(
            faces.isEmpty
                ? 'No face detected.'
                : 'Multiple faces detected.',
          );
        }

        final face = faces.first;

        if (face.score < 0.60) {
          return const FaceVerificationResult.failure(
            'Face detection confidence is too low.',
          );
        }

        final embedding = await _detector!.getFaceEmbedding(
          face,
          bytes,
        );

        embeddings.add(
          embedding.map((value) => value.toDouble()).toList(),
        );

        onProgress?.call(sample + 1, samples);
      }

      final current = _centroid(embeddings);
      final score = _cosine(enrolledEmbedding, current);

      return FaceVerificationResult(
        matched: score >= verificationThreshold,
        score: score,
        message: score >= verificationThreshold
            ? 'Identity verified.'
            : 'Identity not recognized.',
      );
    } catch (error) {
      return FaceVerificationResult.failure(
        'Face verification failed: $error',
      );
    } finally {
      _running = false;
    }
  }

  List<double> _centroid(List<List<double>> values) {
    if (values.isEmpty) return const [];

    final result = List<double>.filled(
      values.first.length,
      0,
    );

    for (final value in values) {
      for (var index = 0; index < result.length; index++) {
        result[index] += value[index];
      }
    }

    for (var index = 0; index < result.length; index++) {
      result[index] /= values.length;
    }

    return result;
  }

  double _cosine(
    List<double> left,
    List<double> right,
  ) {
    if (left.length != right.length || left.isEmpty) {
      return -1;
    }

    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;

    for (var index = 0; index < left.length; index++) {
      dot += left[index] * right[index];
      leftNorm += left[index] * left[index];
      rightNorm += right[index] * right[index];
    }

    if (leftNorm == 0 || rightNorm == 0) return -1;

    return dot /
        (math.sqrt(leftNorm) * math.sqrt(rightNorm));
  }

  Future<bool> hasEnrollment() async {
    final file = await _identityFile();
    return file.exists();
  }

  Future<List<double>?> loadEnrollment() async {
    try {
      final file = await _identityFile();

      if (!await file.exists()) return null;

      final decoded = jsonDecode(
        await file.readAsString(),
      );

      if (decoded is! Map) return null;

      final values = decoded['embedding'];

      if (values is! List) return null;

      return values
          .map((value) => (value as num).toDouble())
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> resetEnrollment() async {
    final file = await _identityFile();

    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> dispose() async {
    await _detector?.dispose();
    _detector = null;
  }

  Future<void> _saveIdentity(
    List<double> embedding,
  ) async {
    final file = await _identityFile();

    await file.parent.create(recursive: true);

    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'createdAt': DateTime.now().toIso8601String(),
        'embedding': embedding,
      }),
      flush: true,
    );
  }

  Future<File> _identityFile() async {
    final directory =
        await getApplicationSupportDirectory();

    return File(
      '${directory.path}${Platform.pathSeparator}'
      'CronyX${Platform.pathSeparator}'
      'identity${Platform.pathSeparator}'
      'face_identity.json',
    );
  }
}

final class FaceEnrollmentResult {
  const FaceEnrollmentResult._({
    required this.success,
    this.embedding,
    this.message,
  });

  const FaceEnrollmentResult.success(
    List<double> embedding,
  ) : this._(
        success: true,
        embedding: embedding,
      );

  const FaceEnrollmentResult.failure(
    String message,
  ) : this._(
        success: false,
        message: message,
      );

  final bool success;
  final List<double>? embedding;
  final String? message;
}

final class FaceVerificationResult {
  const FaceVerificationResult({
    required this.matched,
    required this.score,
    required this.message,
  });

  const FaceVerificationResult.failure(
    String message,
  ) : this(
        matched: false,
        score: -1,
        message: message,
      );

  final bool matched;
  final double score;
  final String message;
}
