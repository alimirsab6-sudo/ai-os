import '../../core/result.dart';

abstract interface class VoiceAssistant {
  bool get hasOwnerProfile;
  bool get ownerVerified;
  bool get wakeMonitoring;

  Future<Result<void>> initialize();

  Future<Result<void>> enrollOwner(String displayName);

  Future<Result<void>> resetOwnerProfile();

  Future<Result<void>> startWakeMonitoring();

  Future<Result<void>> stopListening();

  Future<Result<String>> describeSecurityActivity();

  Future<void> dispose();
}
