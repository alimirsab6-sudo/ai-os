import 'dart:io';
import 'dart:typed_data';

import '../../core/result.dart';
import 'local_voice_runtime.dart';

final class WindowsVoiceRuntime implements LocalVoiceRuntime {
  WindowsVoiceRuntime({
    required this.paths,
  });

  final VoiceRuntimePaths paths;

  bool _initialized = false;

  @override
  Future<Result<void>> initialize() async {
    print('[STT] INITIALIZING');

    try {
      final result = await Process.run(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Add-Type -AssemblyName System.Speech; Write-Output SPEECH_OK',
        ],
      );

      print('[STT] exitCode=${result.exitCode}');
      print('[STT] stdout=${result.stdout}');
      print('[STT] stderr=${result.stderr}');

      if (result.exitCode != 0 ||
          !result.stdout.toString().contains('SPEECH_OK')) {
        return Result.failure(
          Failure(
            'Windows Speech Recognition is unavailable.',
            code: 'stt_backend_unavailable',
          ),
        );
      }

      _initialized = true;

      print('[STT] WINDOWS SPEECH READY');

      return const Result.success(null);
    } catch (error, stackTrace) {
      print('[STT] INIT ERROR: $error');
      print('[STT] $stackTrace');

      return Result.failure(
        Failure(
          'Could not initialize speech recognition: $error',
          code: 'stt_initialization_failed',
        ),
      );
    }
  }

  @override
  Future<Result<String>> transcribe(Float32List samples) async {
    print('[STT] ========================================');
    print('[STT] TRANSCRIBE');
    print('[STT] samples=${samples.length}');

    if (!_initialized) {
      return Result.failure(
        const Failure(
          'Voice runtime has not been initialized.',
          code: 'runtime_not_initialized',
        ),
      );
    }

    if (samples.isEmpty) {
      return Result.failure(
        const Failure(
          'No microphone audio was received.',
          code: 'empty_audio',
        ),
      );
    }

    Directory? tempDirectory;
    File? wavFile;

    try {
      tempDirectory = await Directory.systemTemp.createTemp(
        'cronyx_stt_',
      );

      wavFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}speech.wav',
      );

      final pcm = _float32ToPcm16(samples);
      final wav = _makeWav(pcm);

      await wavFile.writeAsBytes(
        wav,
        flush: true,
      );

      print('[STT] WAV CREATED');
      print('[STT] path=${wavFile.path}');
      print('[STT] bytes=${wav.length}');

      final path = wavFile.path.replaceAll("'", "''");

      final script = '''
Add-Type -AssemblyName System.Speech

\$recognizer = New-Object System.Speech.Recognition.SpeechRecognitionEngine

try {
    \$recognizer.LoadGrammar(
        (New-Object System.Speech.Recognition.DictationGrammar)
    )

    \$recognizer.SetInputToWaveFile('$path')

    \$result = \$recognizer.Recognize(
        [TimeSpan]::FromSeconds(8)
    )

    if (\$null -eq \$result) {
        Write-Output "NO_SPEECH"
    }
    else {
        Write-Output \$result.Text
    }
}
finally {
    \$recognizer.Dispose()
}
''';

      print('[STT] RUNNING WINDOWS SPEECH...');

      final result = await Process.run(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ],
      );

      final stdout = result.stdout.toString().trim();
      final stderr = result.stderr.toString().trim();

      print('[STT] exitCode=${result.exitCode}');
      print('[STT] stdout=$stdout');

      if (stderr.isNotEmpty) {
        print('[STT] stderr=$stderr');
      }

      if (result.exitCode != 0) {
        return Result.failure(
          Failure(
            'Windows speech recognition failed: $stderr',
            code: 'stt_failed',
          ),
        );
      }

      if (stdout.isEmpty || stdout == 'NO_SPEECH') {
        print('[STT] NO SPEECH RECOGNIZED');

        return Result.failure(
          const Failure(
            'Could not understand the microphone audio.',
            code: 'speech_not_recognized',
          ),
        );
      }

      final lines = stdout
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      if (lines.isEmpty) {
        return Result.failure(
          const Failure(
            'Could not understand the microphone audio.',
            code: 'speech_not_recognized',
          ),
        );
      }

      final transcript = lines.last;

      print('[STT] ========================================');
      print('[STT] TRANSCRIPT: "$transcript"');
      print('[STT] ========================================');

      return Result.success(transcript);
    } catch (error, stackTrace) {
      print('[STT] TRANSCRIPTION ERROR: $error');
      print('[STT] $stackTrace');

      return Result.failure(
        Failure(
          'Speech transcription failed: $error',
          code: 'stt_transcription_failed',
        ),
      );
    } finally {
      try {
        if (wavFile != null && await wavFile.exists()) {
          await wavFile.delete();
        }

        if (tempDirectory != null &&
            await tempDirectory.exists()) {
          await tempDirectory.delete();
        }
      } catch (_) {}
    }
  }

  Uint8List _float32ToPcm16(Float32List samples) {
    final output = Uint8List(samples.length * 2);
    final data = ByteData.sublistView(output);

    for (var i = 0; i < samples.length; i++) {
      var sample = samples[i];

      if (sample > 1.0) {
        sample = 1.0;
      }

      if (sample < -1.0) {
        sample = -1.0;
      }

      final value = (sample * 32767).round();

      data.setInt16(
        i * 2,
        value,
        Endian.little,
      );
    }

    return output;
  }

  Uint8List _makeWav(Uint8List pcm) {
    const sampleRate = 16000;
    const channels = 1;
    const bitsPerSample = 16;

    final byteRate =
        sampleRate * channels * bitsPerSample ~/ 8;

    final blockAlign =
        channels * bitsPerSample ~/ 8;

    final wav = Uint8List(
      44 + pcm.length,
    );

    final data = ByteData.sublistView(wav);

    void text(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        wav[offset + i] = value.codeUnitAt(i);
      }
    }

    text(0, 'RIFF');

    data.setUint32(
      4,
      36 + pcm.length,
      Endian.little,
    );

    text(8, 'WAVE');
    text(12, 'fmt ');

    data.setUint32(
      16,
      16,
      Endian.little,
    );

    data.setUint16(
      20,
      1,
      Endian.little,
    );

    data.setUint16(
      22,
      channels,
      Endian.little,
    );

    data.setUint32(
      24,
      sampleRate,
      Endian.little,
    );

    data.setUint32(
      28,
      byteRate,
      Endian.little,
    );

    data.setUint16(
      32,
      blockAlign,
      Endian.little,
    );

    data.setUint16(
      34,
      bitsPerSample,
      Endian.little,
    );

    text(36, 'data');

    data.setUint32(
      40,
      pcm.length,
      Endian.little,
    );

    wav.setRange(
      44,
      44 + pcm.length,
      pcm,
    );

    return wav;
  }

  @override
  Future<Result<Float32List>> createSpeakerEmbedding(
    Float32List samples,
  ) async {
    if (!_initialized) {
      return Result.failure(
        const Failure(
          'Voice runtime has not been initialized.',
          code: 'runtime_not_initialized',
        ),
      );
    }

    return Result.failure(
      const Failure(
        'Speaker embedding backend is not configured yet.',
        code: 'speaker_backend_unavailable',
      ),
    );
  }

  @override
  Future<Result<bool>> detectWakePhrase(
    Float32List samples,
  ) async {
    if (!_initialized) {
      return Result.failure(
        const Failure(
          'Voice runtime has not been initialized.',
          code: 'runtime_not_initialized',
        ),
      );
    }

    return const Result.success(false);
  }

  @override
  Future<Result<void>> resetWakePhrase() async {
    return const Result.success(null);
  }

  @override
  Future<void> dispose() async {
    print('[STT] DISPOSE');
    _initialized = false;
  }
}
