enum AiCoreState {
  idle,
  listening,
  thinking,
  speaking,
  executing,
  success,
  error,
}

enum AiCoreQuality { low, medium, high }

extension AiCoreQualityValue on AiCoreQuality {
  double get shaderValue => switch (this) {
    AiCoreQuality.low => 0,
    AiCoreQuality.medium => 1,
    AiCoreQuality.high => 2,
  };
}

