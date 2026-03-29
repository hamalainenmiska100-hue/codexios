# CodexLocal

CodexLocal is a local-first iOS app that emulates a Codex-style coding shell on top of a user-selected writable folder.

## What is real in this app

- Folder access uses iOS security-scoped bookmarks.
- The app can list, read, create, update, delete, and export files inside the chosen workspace folder.
- Editor changes are saved back to the actual selected folder.
- Credentials can be kept entirely on device:
  - local session mode
  - imported `auth.json`
  - API key stored in Keychain

## What is intentionally simulated

- The container runtime is local state, not a real Docker container.
- Shell commands are emulated with deterministic outputs.
- The main file automation path is a local Codex-style heuristic engine.
- The optional Foundation Models toggle is included as an experimental on-device text generation lane. The stable path for actual file automation is the heuristic local engine.

## Included features

- Modern three-pane SwiftUI layout
- Chat timeline with visible thinking and tool events
- Folder tree and real file editor
- Approval queue for writes
- Export selected file to another folder
- Container state inspector with command history, changed files, logs, and processes
- Unsigned IPA GitHub Actions workflow

## Project layout

- `CodexLocal/`
  - `CodexLocalApp.swift`
  - `AppModel.swift`
  - `Models.swift`
  - `Services.swift`
  - `Engine.swift`
  - `FoundationModelsIntegration.swift`
  - `Views.swift`
  - `Assets.xcassets/`
- `CodexLocal.xcodeproj/`
- `.github/workflows/ios-unsigned-ipa.yml`

## Build locally

1. Open `CodexLocal.xcodeproj` in Xcode 26 or newer.
2. Keep the deployment target on iOS 26.
3. Build and run on a device or simulator.
4. On first launch:
   - choose **Use local session**
   - choose a workspace folder
   - optionally choose an export folder

## Unsigned IPA in GitHub Actions

The workflow builds the app without code signing and packages the `.app` bundle into an unsigned `.ipa` artifact named `CodexLocal-unsigned-ipa`.

## Notes

- This template is intentionally self-contained and has no backend.
- If you want a real external model later, add your networking layer in `AppModel` and `Engine`.
- If you want stricter container semantics, swap `ContainerRuntime` for a real companion runtime on macOS or a remote worker.
