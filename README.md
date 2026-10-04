# ScreenshotMaxxing

ScreenshotMaxxing is a local-first native macOS capture utility. It lives in the menu bar, supports keyboard shortcuts, captures screenshots and screen recordings, opens captures in lightweight editors, supports adjustable pixelated blur-based obscuration for screenshots, and stores captures locally.

## Features

- Area, window, and fullscreen screenshot capture.
- Area, window, and fullscreen video recording.
- Optional microphone and system-audio recording.
- Screenshot annotation, copy, save, and local edited-file output.
- Video playback and editing workflow.
- Local capture history with screenshots, recordings, and thumbnails.
- Configurable keyboard shortcuts.

## Privacy

ScreenshotMaxxing is designed to work offline. It does not use accounts, subscriptions, usage tracking, hosted capture libraries, or cloud sync.

Captures, recordings, edits, thumbnails, and metadata stay on your Mac unless you explicitly share, copy, save, back up, or sync them through macOS or another app. See [PRIVACY.md](PRIVACY.md) for storage locations, permission behavior, and blur/redaction limitations.

## Distribution

Official builds are the signed and notarized DMGs published by Ben Kramer from this repository. The public [benmkramer/tap cask](https://github.com/benmkramer/homebrew-tap/blob/main/Casks/screenshotmaxxing.rb) installs the same official DMG, with its SHA-256 checked by Homebrew. Builds from forks, local source checkouts, or other distribution channels are unofficial and may have different code signing, notarization, update, or bundle identity behavior.

### Homebrew

Requires macOS 26.2 or later on Apple Silicon or Intel. After the cask is merged into the tap:

```sh
brew install --cask benmkramer/tap/screenshotmaxxing
open -a ScreenshotMaxxing
```

Quit the app before upgrading or uninstalling:

```sh
brew update
brew upgrade --cask benmkramer/tap/screenshotmaxxing
brew uninstall --cask benmkramer/tap/screenshotmaxxing
```

The cask follows stable releases only. Upgrades and normal uninstall preserve captures, local history, and preferences. The cask has no `zap` stanza. Homebrew uses the original release bundle identity, so macOS manages Screen Recording and optional Microphone permissions as usual.

If you already installed the DMG manually, quit the app and move only `/Applications/ScreenshotMaxxing.app` to Trash before installing the cask. Keep your data in `~/Library/Application Support/ScreenshotMaxxing/`. Homebrew refuses to overwrite an existing app by default.

Homebrew distribution is maintained using the setup in [docs/RELEASING.md](docs/RELEASING.md#homebrew-distribution).

## Branding And Forks

The MIT License grants broad rights to use, modify, and redistribute the code. Please do not present modified builds as official ScreenshotMaxxing releases or use the app name, icon, or release channels in a way that implies endorsement without permission.

## Documentation

- [Privacy](PRIVACY.md)
- [Contributing](CONTRIBUTING.md)
- [Support](SUPPORT.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Releasing](docs/RELEASING.md)
- [Product plan](docs/PRD.md)
- [Implementation plans](docs/plans/README.md)

## License

ScreenshotMaxxing is licensed under the MIT License. See [LICENSE](LICENSE).
