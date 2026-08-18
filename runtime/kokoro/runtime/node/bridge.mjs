import { createHash } from "node:crypto";
import { mkdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import { performance } from "node:perf_hooks";
import readline from "node:readline";
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
const outputDir = path.join(kokoroDir, "output", "bridge");
const cacheDir = path.join(outputDir, "cache");
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
const maxTextLength = 2000;
const maxLineLength = 8192;
const cacheVersion = "kokoro-82m-v1-q8-af_bella-speed1";

function writeMessage(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

async function sha256(filePath) {
  return createHash("sha256").update(await readFile(filePath)).digest("hex");
}

function audioCachePath(text) {
  const key = createHash("sha256")
    .update(`${cacheVersion}\n${text}`)
    .digest("hex");
  return path.join(cacheDir, `${key}.wav`);
}

async function isCached(filePath) {
  try {
    return (await stat(filePath)).size > 44;
  } catch {
    return false;
  }
}

export function validateRequest(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, error_code: "invalid_request" };
  }
  if (!/^\d{1,18}$/.test(value.id ?? "")) {
    return { ok: false, error_code: "invalid_request" };
  }
  if (value.operation !== "synthesize") {
    return { ok: false, id: value.id, error_code: "invalid_request" };
  }
  if (
    typeof value.text !== "string" ||
    value.text.trim().length === 0 ||
    value.text.length > maxTextLength
  ) {
    return { ok: false, id: value.id, error_code: "invalid_request" };
  }
  return {
    ok: true,
    request: { id: value.id, text: value.text.trim() },
  };
}

async function loadRuntime() {
  for (const voicePath of [
    originalVoicePath,
    runtimeVoicePath,
    packageVoicePath,
  ]) {
    if ((await sha256(voicePath)) !== expectedVoiceSha256) {
      throw new Error("voice_checksum_mismatch");
    }
  }

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
      session_options: {
        intraOpNumThreads: 2,
        interOpNumThreads: 1,
        executionMode: "sequential",
        graphOptimizationLevel: "all",
      },
    }),
    AutoTokenizer.from_pretrained(tokenizerDir, {
      local_files_only: true,
    }),
  ]);
  await mkdir(cacheDir, { recursive: true });
  return new KokoroTTS(model, tokenizer);
}

async function main() {
  let tts;
  try {
    tts = await loadRuntime();
  } catch (error) {
    writeMessage({
      type: "fatal",
      ok: false,
      error_code:
        error?.message === "voice_checksum_mismatch"
          ? "voice_checksum_mismatch"
          : "runtime_initialization_failed",
    });
    process.exitCode = 1;
    return;
  }

  writeMessage({ type: "ready", voice: "af_bella", sample_rate: 24000 });

  const lines = readline.createInterface({
    input: process.stdin,
    crlfDelay: Infinity,
  });
  let queue = Promise.resolve();
  lines.on("line", (line) => {
    const receivedAt = performance.now();
    const receivedAtEpochMs = Date.now();
    queue = queue.then(async () => {
      if (line.length > maxLineLength) {
        writeMessage({ ok: false, error_code: "invalid_request" });
        return;
      }
      let decoded;
      try {
        decoded = JSON.parse(line);
      } catch {
        writeMessage({ ok: false, error_code: "invalid_request" });
        return;
      }
      const validation = validateRequest(decoded);
      if (!validation.ok) {
        writeMessage(validation);
        return;
      }
      const { id, text } = validation.request;
      try {
        const outputPath = audioCachePath(text);
        const cacheLookupStartedAt = performance.now();
        const cacheHit = await isCached(outputPath);
        const cacheLookupCompletedAt = performance.now();
        if (cacheHit) {
          writeMessage({
            id,
            ok: true,
            audio_path: outputPath,
            sample_rate: 24000,
            channels: 1,
            bits_per_sample: 32,
            format: "wav_ieee_float",
            timing: {
              node_received_epoch_ms: receivedAtEpochMs,
              node_queue_ms: cacheLookupStartedAt - receivedAt,
              cache_lookup_ms: cacheLookupCompletedAt - cacheLookupStartedAt,
              inference_ms: 0,
              wav_write_ms: 0,
              node_total_ms: cacheLookupCompletedAt - receivedAt,
              cache_hit: true,
            },
          });
          return;
        }
        const inferenceStartedAt = performance.now();
        const audio = await tts.generate(text, {
          voice: "af_bella",
          speed: 1,
        });
        const inferenceCompletedAt = performance.now();
        await audio.save(outputPath);
        const wavCreatedAt = performance.now();
        writeMessage({
          id,
          ok: true,
          audio_path: outputPath,
          sample_rate: 24000,
          channels: 1,
          bits_per_sample: 32,
          format: "wav_ieee_float",
          timing: {
            node_received_epoch_ms: receivedAtEpochMs,
            node_queue_ms: inferenceStartedAt - receivedAt,
            cache_lookup_ms:
              cacheLookupCompletedAt - cacheLookupStartedAt,
            inference_ms: inferenceCompletedAt - inferenceStartedAt,
            wav_write_ms: wavCreatedAt - inferenceCompletedAt,
            node_total_ms: wavCreatedAt - receivedAt,
            cache_hit: false,
          },
        });
      } catch {
        writeMessage({ id, ok: false, error_code: "synthesis_failed" });
      }
    });
  });
}

if (fileURLToPath(import.meta.url) === path.resolve(process.argv[1] ?? "")) {
  await main();
}
