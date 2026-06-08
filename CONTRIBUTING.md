# Contributing

Thanks for taking a look at ScreenshotMaxxing. This is a native macOS app built with Swift, SwiftUI, AppKit, SwiftData, and ScreenCaptureKit.

## Project Scope

ScreenshotMaxxing is a local-first Mac utility for screenshots, lightweight editing, local history, and screen recordings. Contributions should preserve these constraints:

- Captures and recordings stay local unless the user explicitly shares or exports them.
- No accounts, telemetry, hosted capture library, or cloud sync.
- Permission prompts should be explained clearly and requested only when needed.
- Blur is an obscuration tool, not a certified irreversible redaction system.
- Official distribution remains the signed and notarized DMG release channel from this repository.

## Development Requirements

Recommended setup:

- macOS with Xcode 26.2 or newer.
- Swift 5 project settings as configured in `ScreenshotMaxxing.xcodeproj`.
- Screen Recording permission for local capture and recording tests.
- Microphone permission only when testing microphone-enabled recordings.

The app target uses a separate Debug bundle identifier:

```text
Debug:  com.benmkramer.ScreenshotMaxxing.dev
Release: com.benmkramer.ScreenshotMaxxing
```

Debug builds appear as `ScreenshotMaxxing Dev` in macOS permission settings. This keeps development permissions separate from the installed official app.

## Building

Open the project in Xcode:

```sh
open ScreenshotMaxxing.xcodeproj
```

Or build from the command line:

```sh
xcodebuild build \
  -project ScreenshotMaxxing.xcodeproj \
  -scheme ScreenshotMaxxing \
  -destination 'platform=macOS'
```

## Testing

Run the main test suite:

```sh
xcodebuild test \
  -project ScreenshotMaxxing.xcodeproj \
  -scheme ScreenshotMaxxing \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

UI tests may require a local GUI session and macOS automation permissions. If the full scheme is blocked by automation setup, run the unit tests first and include the UI-test limitation in your PR notes.

## Resetting Local Permissions

To reset both Debug and Release permission identities on a development machine:

```sh
scripts/reset-permissions.sh
```

After resetting permissions, relaunch the app and re-grant Screen Recording in System Settings.

## Release Builds

Most contributors do not need Developer ID signing or notarization. For a local unsigned/internal testing DMG:

```sh
LOCAL_ONLY=1 scripts/release-dmg.sh
```

Official release details live in [docs/RELEASING.md](docs/RELEASING.md). Do not include Apple certificates, notary credentials, Sparkle private keys, or GitHub release secrets in pull requests.

## Pull Requests

Before opening a pull request:

- Keep changes focused on one behavior or documentation area.
- Update docs when changing permissions, storage, capture behavior, recording behavior, release behavior, or user-facing privacy claims.
- Add or update tests for model logic, persistence behavior, file handling, editor state, and regressions that can be exercised without UI automation.
- Note any manual macOS permission or recording checks you performed.

## Reporting Security Issues

Do not file public GitHub issues for vulnerabilities or privacy-sensitive findings. Use [SECURITY.md](SECURITY.md).
