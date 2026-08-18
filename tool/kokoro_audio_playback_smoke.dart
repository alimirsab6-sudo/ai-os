import 'package:ai_os/voice/audio/windows_speech_audio_player.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final player = WindowsSpeechAudioPlayer(
    diagnostics: (message) => debugPrint('KOKORO_AUDIO_SMOKE $message'),
  );
  const path = r'C:\ai-os\runtime\kokoro\output\cronyx-af_bella-test.wav';
  final result = await player.play(
    path,
    onStarted: () => debugPrint('KOKORO_AUDIO_SMOKE playback_started'),
  );
  result.fold(
    (_) => debugPrint('KOKORO_AUDIO_SMOKE playback_completed'),
    (failure) => debugPrint(
      'KOKORO_AUDIO_SMOKE playback_failed ${failure.code} ${failure.message}',
    ),
  );
  await player.dispose();
}
