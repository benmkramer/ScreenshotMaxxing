# Security Policy

ScreenshotMaxxing handles screen contents, local capture files, optional microphone audio, optional system audio, and release signing infrastructure. Please report security or privacy-sensitive issues privately.

## Supported Versions

Security fixes are handled for the current public release and the current `main` branch.

Older releases may receive fixes when the issue is severe and the release is still reasonably in use, but there is no long-term support policy.

## Reporting A Vulnerability

Please do not open a public GitHub issue for security-sensitive reports.

Report vulnerabilities through GitHub private vulnerability reporting:

```text
https://github.com/benmkramer/ScreenshotMaxxing/security/advisories/new
```

If private vulnerability reporting is not available, contact the repository owner privately before posting details publicly.

Include as much of the following as you can:

- Affected version or commit.
- macOS version.
- Whether the build is an official DMG, local Debug build, or fork.
- Steps to reproduce.
- Expected and actual behavior.
- Any relevant screenshots, recordings, logs, or sample files.
- Whether the issue involves screen contents, microphone audio, system audio, local files, redaction/blur, app permissions, signing, notarization, or release artifacts.

I will acknowledge credible reports as soon as practical and coordinate a fix before public disclosure when appropriate.

## Security-Relevant Areas

Reports are especially useful in these areas:

- Screen Recording permission handling.
- Microphone and system audio recording behavior.
- Local capture, thumbnail, edited-file, and metadata storage.
- Deletion behavior for capture history and related files.
- Blur or redaction claims that may mislead users about recoverability.
- Confused-deputy or time-of-check/time-of-use bugs in window or screen selection.
- Temporary files used during capture, recording, editing, or release.
- Developer ID signing, notarization, release workflows, GitHub Actions, and future auto-update metadata.

## Redaction And Sensitive Content

ScreenshotMaxxing's pixelated blur tool modifies exported pixels, but blur is not certified irreversible redaction. Do not assume blurred secrets are unrecoverable. Security reports about misleading redaction behavior are in scope.

## Secrets

The repository must not contain private signing certificates, certificate passwords, App Store Connect private keys, notary credentials, Sparkle private keys, GitHub personal access tokens, or other deployment secrets.

If you believe a secret was exposed, report it privately and include the file path, commit, or artifact where it appears.
