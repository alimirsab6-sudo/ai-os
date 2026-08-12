# AI OS

AI OS is a native Windows Flutter application being built around a local,
provider-agnostic orchestration core. The final product name and interactive UI
have not been decided.

## Current milestone and capability

Milestone 1 adds the first real PC Agent capability: launch Google Chrome on
Windows through a structured, permission-checked command. The implementation
does not use an LLM and does not accept arbitrary executable or shell input.

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

## Validate

```powershell
flutter analyze
flutter test
flutter build windows
```

## Current limitations

The only real computer-control operation is launching Chrome. There is no
browser navigation, keyboard/mouse automation, terminal execution, real AI
provider, local model, voice feature, external integration, persistent/vector
memory, or MCP networking. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design details.
