# Privacy

ScreenshotMaxxing is designed as a local-first Mac utility. It does not use accounts, subscriptions, telemetry, hosted screenshot libraries, or cloud sync.

This document describes the app's intended privacy behavior for official builds from this repository. Forks and modified builds may behave differently.

## Local Data

ScreenshotMaxxing stores captures and local metadata on your Mac.

By default, capture files are stored under:

```text
~/Library/Application Support/ScreenshotMaxxing/Captures/
  originals/
  edited/
  thumbnails/
```

The app stores capture metadata locally with SwiftData. Metadata includes fields such as file name, creation time, media type, capture mode, dimensions, original file path, edited file path, favorite state, video duration, thumbnail path, and whether microphone or system audio was enabled for a recording.

Screenshots, videos, edits, thumbnails, and metadata are not uploaded by ScreenshotMaxxing. They leave your Mac only when you explicitly share, copy, save, move, back up, or sync them through macOS or another app.

## Permissions

ScreenshotMaxxing asks macOS for permissions only to support capture and recording features.

Screen Recording is required so the app can capture screenshots and record screen video. macOS manages this permission in System Settings.

Microphone access is requested only when you enable microphone audio for a video recording. If microphone recording is disabled, the app should not request microphone access for normal screenshot capture.

System audio recording is optional and controlled by the recording options. It uses macOS screen/audio recording facilities and may require the relevant macOS privacy permission depending on OS behavior.

## Capture And Recording Behavior

Screenshot captures use macOS screen capture APIs and save image files locally.

Video recordings use ScreenCaptureKit and save local MP4 or MOV files. Recordings can include cursor activity and mouse clicks. When microphone audio is enabled, recordings use MOV output. When microphone audio is disabled, recordings use MP4 output.

The app may generate thumbnails for video history. Thumbnails are stored locally with other capture files.

## Editing And Redaction

Blur and other editing tools affect exported files only after you save, copy, or export the edited result. Original files may remain in the `originals/` folder unless you delete them.

Blur is an obscuration tool, not certified irreversible redaction. Stronger blur settings reduce visible detail, but blur should not be treated as a guarantee against recovery or inference for highly sensitive information. For high-risk secrets, prefer cropping, covering with an opaque shape if available, or avoiding capture of the secret in the first place.

## Deletion

When you delete captures from history, ScreenshotMaxxing attempts to remove the related local files and metadata. macOS Trash, backups, sync tools, file recovery tools, or manually copied files may retain separate copies outside the app's control.

## Networking

The app is intended to work offline. It does not send captures, recordings, metadata, usage events, or diagnostics to a hosted service.

Release downloads, GitHub Releases, the project website, and any future auto-update feed are public distribution infrastructure outside the app's local capture workflow.

## Official Builds

Official builds are the signed and notarized DMGs published by Ben Kramer from this repository. Builds from forks, local source checkouts, or other distribution channels may have different code signing, notarization, update, bundle identity, or privacy behavior.

## Contact

For privacy-sensitive bugs or security issues, use the reporting path in [SECURITY.md](SECURITY.md). For normal support questions, see [SUPPORT.md](SUPPORT.md).
