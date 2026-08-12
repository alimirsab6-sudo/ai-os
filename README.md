# AI OS

AI OS is a native Windows Flutter application being built around a local,
provider-agnostic orchestration core. The final product name and interactive UI
have not been decided.

## Current milestone and capability

Milestone 2A adds read-only discovery of visible top-level Windows windows and
the active window. Milestone 1 Chrome launch remains available. Both use
structured, permission-checked commands without an LLM or arbitrary shell input.

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
including process metadata where Windows permits it.

## Validate

```powershell
flutter analyze
flutter test
flutter build windows
```

## Current limitations

The implemented Windows capabilities are limited to launching Chrome and
read-only window discovery. There is no browser navigation, screenshot/OCR,
keyboard/mouse automation, terminal execution, process termination, real AI
provider, local model, voice feature, external integration, persistent/vector
memory, or MCP networking. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design details.
