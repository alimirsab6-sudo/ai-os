final class ChromeProfile {
  const ChromeProfile({
    required this.id,
    required this.displayName,
    required this.directoryIdentifier,
    required this.isDefault,
    this.avatarIcon,
  });

  final String id;
  final String displayName;
  final String directoryIdentifier;
  final bool isDefault;
  final String? avatarIcon;

  Map<String, Object?> toMap() => {
    'profile_id': id,
    'display_name': displayName,
    'directory_identifier': directoryIdentifier,
    'is_default': isDefault,
    'avatar_icon': avatarIcon,
  };
}

final class ResolvedChromeProfile {
  const ResolvedChromeProfile({required this.profile});

  final ChromeProfile profile;

  String get directoryIdentifier => profile.directoryIdentifier;
}

