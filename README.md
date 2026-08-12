# AI OS

AI OS is a native Windows Flutter application being built around a local,
provider-agnostic orchestration core. The final product name and interactive UI
have not been decided.

## Current milestone

Milestone 0B establishes architecture only. It includes result-based failures,
model-provider and agent boundaries, authorization-gated tools, orchestration,
events, local configuration, in-memory storage, skills, an MCP boundary, and a
plain-Dart composition root.

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

## Validate

```powershell
flutter analyze
flutter test
flutter build windows
```

## Current limitations

There are no real AI providers, local models, Windows or browser automation,
voice features, external integrations, persistent/vector memory, or MCP
networking. Placeholder tools and the PC Agent report that execution is not
implemented. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design details.
