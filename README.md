# AI OS

AI OS is a native Windows Flutter application being built around a local,
provider-agnostic orchestration core. The final product name and interactive UI
have not been decided.

## Current milestone and capability

Phase 1 connects the approved CronyX command bar and Quick Actions to the
existing orchestrator, agents, permission boundary, tools, result types, and
event bus. Controlled text such as `Open Chrome`, `Open Microsoft Edge`,
`Open Notepad`, `Open Calculator`, `Open File Explorer`, `Open Windows
Settings`, and `Open https://example.com` is interpreted deterministically and
routed as a structured command. Text is never passed to a terminal or shell.

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
then idle. Microphone, speech, and voice remain visual-only and unconnected.

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
launching, validated HTTP(S) URL opening, discovering and launching validated
local Chrome profiles,
top-level window discovery/control, bounded accessibility-tree inspection,
semantic Invoke, and Value/SetValue. Selection, Toggle, ExpandCollapse, Scroll,
RangeValue, and Text actions are not executable. There is no
tab management, in-page website interaction, screenshot/OCR, keyboard/mouse
automation, terminal execution, process termination, real AI provider, local
model, voice feature, external integration, persistent/vector memory, or MCP
networking. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design details.

BrowserSession currently stores only the selected Chrome profile. Navigation,
tabs, page interaction, browser verification beyond safe selected-profile
metadata, and all later Browser Agent capabilities remain unimplemented.
