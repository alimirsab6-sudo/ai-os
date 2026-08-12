# AI OS

AI OS is a native Windows Flutter application being built around a local,
provider-agnostic orchestration core. The final product name and interactive UI
have not been decided.

## Current milestone and capability

Milestone 3A adds read-only inspection of the Microsoft UI Automation control
tree inside a discovered top-level window. Existing window control, discovery,
and Chrome launch remain available. All capabilities use structured,
permission-checked commands without an LLM or arbitrary shell input.

The app currently uses a deterministic mock model provider and a temporary
non-interactive Flutter shell.

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

## Validate

```powershell
flutter analyze
flutter test
flutter build windows
```

## Current limitations

The implemented Windows capabilities are limited to launching Chrome,
top-level window discovery/control, and bounded read-only accessibility-tree
inspection. There is no UI-element action, browser-specific automation,
navigation, screenshot/OCR, keyboard/mouse automation, terminal execution,
process termination, real AI provider, local model, voice feature, external
integration, persistent/vector memory, or MCP networking. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design details.
