# Phonemizer payload

The selected runtime uses `phonemizer` 1.2.1. Its eSpeak NG engine, English
language data, voices, and WebAssembly runtime are embedded into this single
installed bundle:

`..\runtime\node\node_modules\phonemizer\dist\phonemizer.js`

The bundle is 1,322,380 bytes. No external eSpeak installation or separate
phonemizer data download is required, and this directory intentionally does
not duplicate the embedded payload.

