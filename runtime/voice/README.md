# CronyX local voice runtime

CronyX voice input is local-only. Windows uses `record` for 16 kHz mono PCM16
capture and sherpa-onnx 1.13.6 for Moonshine v2 tiny English STT, the 3M
Zipformer `Crony` keyword spotter, and English VoxCeleb WeSpeaker
embeddings. Kokoro-82M and `af_bella` remain the speech-output system.

## Enrollment and reset

Run `Enroll my voice as Ali` in the existing command bar. The name is
configurable; Ali is only an example. CronyX captures three prompted samples.
Audio remains in memory and is discarded after embedding extraction.

Run `Reset voice profile` to remove the profile. It is stored under the current
Windows user's application-support directory at
`CronyX\voice\owner_profile.json`. It contains the display name, model ID,
timestamp, and one normalized 256-value centroid embedding—no audio or
transcript.

## Verification and privacy

Cosine similarity must be at least `0.75`. Lower scores remain unknown, which
favors false rejection over false acceptance. Speaker recognition is a
convenience identity signal, not cryptographic authentication, and never
replaces tool permissions. The wake phrase and spoken name do not authenticate
anyone.

No microphone audio, transcript, embedding, or profile is uploaded. Unknown
speaker events are memory-only for the current session and contain only a
timestamp, event ID, result, and optional voluntarily provided name.

## Manual Windows validation

1. Run `flutter run -d windows` from the project root.
2. Enroll with `Enroll my voice as <name>` and speak all three prompts.
3. Say `Crony`, then `Open Calculator` after verification.
4. Use a second physical speaker and confirm the same wake phrase remains
   locked.
5. Have the owner return and confirm the unknown-speaker notice occurs once.

Physical owner/second-speaker threshold calibration is mandatory before this
feature can be called production-ready.
