import { createHash } from "node:crypto";
import { mkdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  AutoTokenizer,
  StyleTextToSpeech2Model,
  env as transformersEnv,
} from "@huggingface/transformers";
import { KokoroTTS } from "kokoro-js";

const runtimeNodeDir = path.dirname(fileURLToPath(import.meta.url));
const kokoroDir = path.resolve(runtimeNodeDir, "..", "..");
const projectDir = path.resolve(kokoroDir, "..", "..");
const modelDir = path.join(kokoroDir, "model");
const tokenizerDir = path.join(kokoroDir, "tokenizer");
const outputDir = path.join(kokoroDir, "output");
const outputPath = path.join(outputDir, "cronyx-af_bella-test.wav");
const originalVoicePath = path.join(projectDir, "af_bella.bin");
const runtimeVoicePath = path.join(kokoroDir, "voices", "af_bella.bin");
const packageVoicePath = path.join(
  runtimeNodeDir,
  "node_modules",
  "kokoro-js",
  "voices",
  "af_bella.bin",
);
const expectedVoiceSha256 =
  "f69d836209b78eb8c66e75e3cda491e26ea838a3674257e9d4e5703cbaf55c8b";

async function sha256(filePath) {
  return createHash("sha256").update(await readFile(filePath)).digest("hex");
}

for (const voicePath of [
  originalVoicePath,
  runtimeVoicePath,
  packageVoicePath,
]) {
  const actual = await sha256(voicePath);
  if (actual !== expectedVoiceSha256) {
    throw new Error(`Voice checksum mismatch for ${voicePath}: ${actual}`);
  }
}

// Enforce local-only model/tokenizer resolution during initialization and inference.
transformersEnv.allowLocalModels = true;
transformersEnv.allowRemoteModels = false;
transformersEnv.useFSCache = false;

const config = JSON.parse(
  await readFile(path.join(tokenizerDir, "config.json"), "utf8"),
);

const [model, tokenizer] = await Promise.all([
  StyleTextToSpeech2Model.from_pretrained(modelDir, {
    config,
    device: "cpu",
    dtype: "q8",
    subfolder: "",
    local_files_only: true,
  }),
  AutoTokenizer.from_pretrained(tokenizerDir, {
    local_files_only: true,
  }),
]);

const tts = new KokoroTTS(model, tokenizer);
const text = "Good morning. I'm CronyX. How may I assist you today?";
const audio = await tts.generate(text, { voice: "af_bella" });

await mkdir(outputDir, { recursive: true });
await audio.save(outputPath);

const wav = await readFile(outputPath);
const result = {
  offlineOnly: transformersEnv.allowRemoteModels === false,
  text,
  voice: "af_bella",
  sampleRateHz: audio.sampling_rate,
  channels: wav.readUInt16LE(22),
  bitsPerSample: wav.readUInt16LE(34),
  audioFormatCode: wav.readUInt16LE(20),
  sampleCount: audio.audio.length,
  durationSeconds: audio.audio.length / audio.sampling_rate,
  outputPath,
  outputBytes: (await stat(outputPath)).size,
  outputSha256: await sha256(outputPath),
};

console.log(JSON.stringify(result, null, 2));

