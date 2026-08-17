import 'package:flutter/foundation.dart';

import 'ai_core_state.dart';

/// Development-facing visual state for the Living AI Core.
///
/// This controller deliberately has no dependency on agents, tools, voice, or
/// orchestration. Those systems may drive it through a separate adapter later.
final class AiCoreController extends ChangeNotifier {
  AiCoreController({
    AiCoreState state = AiCoreState.idle,
    AiCoreQuality quality = AiCoreQuality.medium,
    bool mouseInteraction = true,
    double intensity = 1,
    double speechIntensity = 0.72,
  }) {
    _state = state;
    _quality = quality;
    _mouseInteraction = mouseInteraction;
    _intensity = intensity.clamp(0.35, 1.5).toDouble();
    _speechIntensity = speechIntensity.clamp(0, 1).toDouble();
  }

  late AiCoreState _state;
  late AiCoreQuality _quality;
  late bool _mouseInteraction;
  late double _intensity;
  late double _speechIntensity;

  AiCoreState get state => _state;
  AiCoreQuality get quality => _quality;
  bool get mouseInteraction => _mouseInteraction;
  double get intensity => _intensity;
  double get speechIntensity => _speechIntensity;

  void setState(AiCoreState value) {
    if (_state == value) return;
    _state = value;
    notifyListeners();
  }

  void setQuality(AiCoreQuality value) {
    if (_quality == value) return;
    _quality = value;
    notifyListeners();
  }

  void setMouseInteraction(bool value) {
    if (_mouseInteraction == value) return;
    _mouseInteraction = value;
    notifyListeners();
  }

  void setIntensity(double value) {
    final next = value.clamp(0.35, 1.5).toDouble();
    if (_intensity == next) return;
    _intensity = next;
    notifyListeners();
  }

  void setSpeechIntensity(double value) {
    final next = value.clamp(0, 1).toDouble();
    if (_speechIntensity == next) return;
    _speechIntensity = next;
    notifyListeners();
  }
}
