# CronyX local Kokoro runtime

This directory contains a standalone local verification runtime for
Kokoro-82M v1.0 ONNX. It is not integrated with Flutter.

## Assets

- `model/model_quantized.onnx`: official `onnx-community/Kokoro-82M-v1.0-ONNX`
  q8 model, 92,361,116 bytes, SHA-256
  `fbae9257e1e05ffc727e951ef9b9c98418e6d79f1c9b6b13bd59f5c9028a1478`.
- `voices/af_bella.bin`: verified copy of `C:\ai-os\af_bella.bin`, 522,240
  bytes, SHA-256
  `f69d836209b78eb8c66e75e3cda491e26ea838a3674257e9d4e5703cbaf55c8b`.
- `tokenizer/`: upstream `tokenizer.json`, `tokenizer_config.json`, and
  `config.json`.
- `runtime/node/`: pinned `kokoro-js` 1.2.1 runtime, including
  Transformers.js 3.8.1, ONNX Runtime Node 1.21.0, and phonemizer 1.2.1.
- `phonemizer/README.md`: location and packaging details for the embedded
  eSpeak NG phonemizer data.

## Offline verification

From `runtime/kokoro/runtime/node`, run:

```powershell
$env:HTTP_PROXY = 'http://127.0.0.1:1'
$env:HTTPS_PROXY = 'http://127.0.0.1:1'
$env:NO_PROXY = ''
& 'C:\Program Files\nodejs\node.exe' '.\verify-offline.mjs'
```

The verifier also sets `allowRemoteModels = false` and
`local_files_only = true`. It checks all `af_bella` copies against the
expected checksum before inference. Its output is
`output/cronyx-af_bella-test.wav`.

