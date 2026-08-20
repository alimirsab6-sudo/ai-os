import 'package:camera/camera.dart';

final class FaceCameraService {
  CameraController? _controller;

  CameraController? get controller => _controller;

  bool get isInitialized => _controller?.value.isInitialized ?? false;

  Future<CameraController> initialize() async {
    final cameras = await availableCameras();

    if (cameras.isEmpty) {
      throw StateError('No camera was found.');
    }

    CameraDescription selected = cameras.first;

    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.front) {
        selected = camera;
        break;
      }
    }

    final controller = CameraController(
      selected,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await controller.initialize();

    _controller = controller;
    return controller;
  }

  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;

    if (controller != null) {
      await controller.dispose();
    }
  }
}
