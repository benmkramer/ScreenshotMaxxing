# Architecture

ScreenshotMaxxing is a local-first native macOS utility. It is built with Swift, SwiftUI, AppKit, SwiftData, CoreImage/CoreGraphics, AVFoundation, and ScreenCaptureKit.

## Product Boundaries

The app intentionally avoids accounts, telemetry, hosted screenshot libraries, subscriptions, and cloud sync. Captures, recordings, edits, thumbnails, and metadata stay on the user's Mac unless the user explicitly shares, copies, saves, backs up, or syncs them through macOS or another app.

Official distribution is a signed and notarized Developer ID DMG. Release mechanics are documented in [RELEASING.md](RELEASING.md).

## App Entry

- `ScreenshotMaxxingApp.swift` creates the SwiftUI app and installs the AppKit delegate.
- `AppDelegate.swift` owns the app-level controllers, menu actions, capture flow, recording flow, editor windows, history windows, preferences windows, and permission onboarding.
- `MenuBar/` owns the status item and menu structure.

The app is configured as an agent-style menu bar app with `LSUIElement`.

## Capture Flow

Screenshot capture code lives in `Capture/`.

- `CaptureController` invokes `/usr/sbin/screencapture` for area, window, and fullscreen screenshots.
- `CaptureMode` maps user-facing capture modes to file naming and `screencapture` arguments.
- `FileLocations` creates local capture directories and unique file names.
- Successful captures are persisted through `CaptureMetadataStore` and then opened in the screenshot editor.

Screenshots are written to the local `originals/` folder.

## Recording Flow

Screen recording code also lives in `Capture/`.

- `RecordingController` uses ScreenCaptureKit to record area, window, or fullscreen video.
- `RecordingModels` defines recording modes, options, output containers, and recording results.
- `RecordingWindowSelectionController` handles window selection for recording.
- `RecordingToolbarWindowController` shows stop/restart controls while recording.
- `RecordingSelectionOverlays` draws the selected area focus overlay.
- `RecordingSettingsStore` persists the user's microphone and system-audio recording options.

Recordings are saved locally as MP4 or MOV files. Microphone-enabled recordings use MOV output. Video thumbnails are generated for local history.

## Editor Flow

Screenshot editing code lives in `Editor/`.

- `ScreenshotEditorWindowController` creates the editor window.
- `ScreenshotEditorView` renders the editor UI and user interactions.
- `ScreenshotEditorState` manages annotation state, selection, tool settings, undoable editing state, and export state.
- `Annotation` and `EditorTool` define supported annotations and tools.
- `ImageRenderer` bakes annotations into exported bitmap pixels.
- `EditorFileSaver` and `EditorClipboard` handle save/copy operations.

Blur annotations are rendered into exported pixels, but blur is an obscuration tool rather than certified irreversible redaction.

Video editing code lives in `Video/`.

- `VideoEditorWindowController` creates video editor windows.
- `VideoEditorView` owns the playback and editing UI.
- `VideoExporter` exports edited clips.
- `VideoMetadata` reads duration, dimensions, and thumbnails.
- `VideoSilenceDetector` supports audio-aware editing workflows.

## History And Persistence

- `Persistence/Capture.swift` is the SwiftData model for local capture metadata.
- `Persistence/CaptureMetadataStore.swift` creates, updates, and deletes capture metadata.
- `History/CaptureHistoryView.swift` renders local history.
- `History/CaptureHistoryData.swift` centralizes history display and file-deletion helpers.

Capture media files are stored outside SwiftData. SwiftData stores metadata and file paths.

Default file layout:

```text
~/Library/Application Support/ScreenshotMaxxing/Captures/
  originals/
  edited/
  thumbnails/
```

## Permissions

Permission onboarding lives in `Permissions/`.

- `ScreenCapturePermissionController` checks and requests Screen Recording permission.
- `DirectScreenAccessController` runs the first capture check after Screen Recording is granted.
- `AppPermissionController` aggregates permission state for onboarding.
- `PermissionOnboardingView` and `PermissionOnboardingWindowController` present setup UI.

Microphone access is requested by `RecordingController` only when microphone recording is enabled.

## Preferences And Shortcuts

- `Preferences/` owns user-facing settings.
- `Shortcuts/HotKeyManager.swift` registers global keyboard shortcuts.
- `Shortcuts/ShortcutSettingsStore.swift` persists shortcut configuration.

Debug and Release builds use separate bundle identifiers so macOS permissions for local development do not collide with the official installed app.

## Release And Website

- `scripts/release-dmg.sh` builds the app, exports a Developer ID app, creates the DMG, and can notarize/staple it.
- `.github/workflows/prepare-release.yml` opens version bump PRs.
- `.github/workflows/release-dmg.yml` builds, signs, notarizes, uploads, and publishes release DMGs.
- `.github/workflows/deploy-site.yml` deploys the static website in `site/`.

The release path should keep signing and notary secrets out of the repository.
