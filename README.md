# AI OS

## Local voice assistant

CronyX has an offline Windows voice pipeline built around the existing
architecture:

```text
Microphone → Crony → speaker verification → local STT
→ existing Command Interpreter → Orchestrator → Agent → Tool → permission
→ Kokoro af_bella response
```

Enroll through the existing command bar with `Enroll my voice as <name>`.
Profiles remain local and contain only a normalized speaker embedding plus
minimal identity metadata. `Reset voice profile` removes the profile. Unknown
voices remain locked even if they speak the owner's name.

See [runtime/voice/README.md](runtime/voice/README.md) for privacy, threshold,
enrollment, reset, models, and manual Windows testing.

AI OS is a native Windows Flutter application being built around a local,
provider-agnostic orchestration core. The final product name and interactive UI
have not been decided.

## Current milestone and capability

Phase 3V-B connects the verified local Kokoro runtime to CronyX command
responses while preserving the approved shell and existing command pipeline.
The permanent layout is navigation plus the Living Core on the
left, the selected Core or large Browser workspace in the center, Live Action /
Activity / implemented Quick Actions on the right, and the existing command
bar floating over the full-height center workspace. Controlled text such as
`Open YouTube`, `Open Google`, and `Go to https://example.com` is routed through
the deterministic interpreter, Orchestrator, Browser Agent, authorized
embedded-browser tool, and `BrowserController`; it does not open external
Chrome or Edge.

Existing Phase 1 commands such as `Open Chrome`, `Open Microsoft Edge`,
`Open Notepad`, `Open Calculator`, `Open File Explorer`, `Open Windows
Settings`, plus external-launch abstractions and tests, remain intact. Text is
never passed to a terminal or shell.

Existing Chrome-profile operations, semantic Invoke and SetValue, UI
inspection, and window discovery/control remain available.

## AI Core Visual Prototype

The application now opens on the visual-only Living AI Core world foundation.
A GPU fragment shader ray-marches a procedural 3D
field of violet, magenta, blue, cyan, and lavender particles. Its sampling
domain continuously deforms, so particles flow through asymmetric, compressed,
elongated, and expanding forms instead of rotating as a fixed globe.
Independent cell phases, depth travel, drift, density clouds, and
particle-built energy streams create bright clusters, deep shadows, and an
organic silhouette. There is no drawn sphere, outline, static texture,
embedded reference image, GIF, or video.

The reusable `AiCore` widget supports visual-only `idle`, `listening`,
`thinking`, `speaking`, `executing`, `success`, and `error` states, low/medium/
high shader quality, intensity control, simulated speech intensity, and
smoothly damped, localized 3D mouse interaction. A visual-only controller
smoothly blends state weights. Speaking uses a deterministic phrase, syllable,
pause, and burst envelope to deform different regions rather than applying one
scale animation. Quality levels vary ray-march sampling and procedural detail;
medium is the default for the Intel UHD 620-class target machine.
The full-screen demo includes a restrained development control strip for these
options.

The Core, HUD, Live Action panel, and Activity area now reflect the same real
command lifecycle: thinking while the request is interpreted, executing after
the selected tool starts, success or error from the structured result, and
then idle. Successful user-facing command results are synthesized locally with
the fixed `af_bella` voice. The Core enters `SPEAKING` only after the Windows
audio backend enters its playing state and returns to idle on native playback
completion. The microphone remains visual-only and unconnected.

## Local Kokoro speech

CronyX maintains one controlled Node process running the application-owned
`runtime/kokoro/runtime/node/bridge.mjs` entrypoint. Flutter sends validated
JSON-line `synthesize` requests; the bridge uses only the local Kokoro-82M
model, tokenizer, and fixed `af_bella` voice and returns only a WAV path under
the controlled bridge output directory. The WAV is validated as non-silent
24 kHz, mono, 32-bit IEEE float audio before `audioplayers` sends it to the
Windows Media Foundation backend. Generated speech is stored in a
content-addressed cache whose filenames are SHA-256 hashes of the fixed runtime
version and response text. Cache hits still pass the same WAV validation. The
ONNX CPU session uses the measured two-thread sequential configuration for the
four-logical-core target. No shell, arbitrary script, executable path, voice
selection, remote model download, or network TTS surface is exposed.

Development diagnostics:

```powershell
dart run tool/kokoro_bridge_smoke.dart
flutter run -d windows -t tool/kokoro_audio_playback_smoke.dart
```

The first command primes/measures the deterministic response cache. The second plays the fixed
known-good `runtime/kokoro/output/cronyx-af_bella-test.wav` through the same
Flutter Windows playback adapter used by CronyX.

## Setup

Requirements:

- Windows with Flutter's Windows desktop prerequisites installed
- A Flutter SDK compatible with Dart 3.12 or later

From the repository root:

```powershell
flutter pub get
```

## Run

```powershell
flutter run -d windows
```

Select **Browser** in the existing left navigation, or enter `Open YouTube`,
`Open Google`, or an absolute HTTP(S) address through the CronyX command bar.
The browser toolbar supports Back, Forward, Reload, current URL, page title,
and loading state. Its persistent dedicated profile is stored at
`%LOCALAPPDATA%\CronyX\Browser\Profile`. Returning to Core disposes the
interactive WebView2 session; selecting Browser again creates a fresh session
while reusing that dedicated profile.

## Manual Chrome launch

With Chrome installed in a standard per-machine or per-user Windows location:

```powershell
dart run tool/launch_chrome.dart
```

This development-only entry point always submits
`LaunchApplicationCommand(applicationId: 'chrome')`. It cannot run a user-
supplied command or launch an unregistered application.

## Manual Windows discovery

Query the actual desktop without taking screenshots or interacting with it:

```powershell
dart run tool/discover_windows.dart
```

The command prints the active window and visible titled top-level windows,
including process metadata and runtime IDs where Windows permits it.

## Manual window control

First run discovery and copy the runtime ID of the intended window. Then submit
exactly one supported operation:

```powershell
dart run tool/control_window.dart activate windows:window:1a2b3c
dart run tool/control_window.dart minimize windows:window:1a2b3c
dart run tool/control_window.dart restore windows:window:1a2b3c
dart run tool/control_window.dart maximize windows:window:1a2b3c
```

The ID must still exist in a fresh discovery snapshot. The manual close path is
restricted to a deliberately opened Notepad test window:

```powershell
dart run tool/control_window.dart close windows:window:1a2b3c --confirm-test-window
```

Close requires `sensitive` permission and the development command refuses any
process other than `notepad.exe`. Sensitive permission is not enabled by the
normal application configuration.

## Manual UI inspection

Run window discovery, copy a current runtime window ID, and inspect a bounded
portion of its accessibility tree:

```powershell
dart run tool/inspect_ui.dart windows:window:1a2b3c
dart run tool/inspect_ui.dart windows:window:1a2b3c 5 100
```

The optional values are `maxDepth` and `maxElements`. Defaults are depth 3 and
100 elements; hard ceilings are depth 10 and 500 elements. The command rejects
IDs absent from a fresh discovery snapshot and performs no UI interaction.

## Manual semantic Invoke

Discover a window ID, then list freshly inspected, non-destructive Invoke
candidates without taking action:

```powershell
dart run tool/invoke_ui.dart windows:window:1a2b3c --max-depth=5 --max-elements=100
```

Invoke one candidate only by its displayed numeric index and explicit
confirmation:

```powershell
dart run tool/invoke_ui.dart windows:window:1a2b3c --max-depth=5 --max-elements=100 --select-index=0 --confirm-invoke
```

The utility never accepts an element ID. It excludes common destructive labels
such as Close/Delete and rejects indices outside its fresh discovered list. To
demonstrate stale-ID refusal without invoking anything:

```powershell
dart run tool/invoke_ui.dart windows:window:1a2b3c --select-index=0 --confirm-invoke --stale-test
```

## Manual semantic SetValue

Open a harmless editable application such as Notepad, then list current
windows and select one by its displayed numeric index:

```powershell
dart run tool/set_ui_value.dart
dart run tool/set_ui_value.dart --window-index=3
```

Select a displayed non-password Value element. The utility asks for an exact
`YES` confirmation and accepts the replacement text interactively:

```powershell
dart run tool/set_ui_value.dart --window-index=3 --element-index=0
```

It never accepts a window or element runtime ID, does not accept value text on
the command line, and never prints the submitted value after entry. Add
`--stale-test` to demonstrate safe stale-element refusal.

## Manual Chrome profile discovery

Chrome does not need to be running. The command reads only Chrome's standard
per-user `Local State` configuration and known immediate profile directories:

```powershell
dart run tool/discover_chrome_profiles.dart
```

It prints profile display names and opaque runtime IDs only. It does not read
or print cookies, tokens, passwords, or browsing history.

## Manual profile-aware Chrome launch

List freshly discovered profiles without launching:

```powershell
dart run tool/launch_chrome_profile.dart
```

Launch one displayed profile by numeric index and explicit confirmation:

```powershell
dart run tool/launch_chrome_profile.dart --profile-index=0 --confirm-launch
```

The utility accepts no executable path, profile directory, Chrome argument, or
shell string. The selected opaque ID is resolved through the same in-memory
discovery registry before the launcher internally creates the single
`--profile-directory` argument.

## Validate

```powershell
flutter analyze
flutter test
flutter build windows
```

## Current limitations

The implemented Windows capabilities are limited to allow-listed application
launching, validated HTTP(S) navigation in the embedded CronyX Browser,
discovering and launching validated
local Chrome profiles,
top-level window discovery/control, bounded accessibility-tree inspection,
semantic Invoke, and Value/SetValue. Selection, Toggle, ExpandCollapse, Scroll,
RangeValue, and Text actions are not executable. There is no
tab management, AI-driven in-page clicking/typing, page extraction,
screenshot/OCR, keyboard/mouse automation, JavaScript/CDP control, downloads,
uploads, credential/payment automation, terminal execution, process
termination, real AI provider, local
model, voice feature, external integration, persistent/vector memory, or MCP
networking. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design details.

`BrowserSession` still stores only the selected external Chrome profile; the
embedded CronyX Browser instead uses its isolated WebView2 profile. Tabs,
programmatic page interaction, page reading, downloads/uploads, and credential
automation remain unimplemented.
