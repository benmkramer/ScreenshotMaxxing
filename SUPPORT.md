# Support

Use this document to decide where to report problems or ask questions.

## Security Or Privacy Issues

Do not open public GitHub issues for vulnerabilities, exposed secrets, privacy-sensitive bugs, or reports involving recoverable sensitive screen contents.

Use [SECURITY.md](SECURITY.md).

## Bugs

Open a GitHub issue with:

- ScreenshotMaxxing version.
- macOS version.
- Whether you installed the official DMG, built from source, or used a fork.
- Capture or recording mode: area, window, fullscreen, screenshot, or video.
- Whether microphone or system audio was enabled.
- Whether Screen Recording and Microphone permissions are granted in System Settings.
- Steps to reproduce.
- Expected and actual behavior.
- Any error text shown by the app.

Avoid attaching captures or recordings that contain private information. Redact or recreate the issue with non-sensitive content when possible.

## Feature Requests

Open a GitHub issue and describe:

- The workflow you are trying to improve.
- Why the current app does not cover it.
- Whether it preserves the local-first/no-telemetry/no-account product direction.

Large features such as cloud sync, hosted sharing, accounts, team workflows, or telemetry are intentionally outside the current product direction.

## Official Builds

Official builds are the signed and notarized DMGs published by Ben Kramer from this repository. Builds from forks, local source checkouts, or other distribution channels are unofficial and may have different code signing, permissions, update, or bundle identity behavior.

## Local Development Help

For build, test, permission reset, and release-script details, see [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/RELEASING.md](docs/RELEASING.md).
