# Releasing ScreenshotMaxxing

ScreenshotMaxxing is distributed as a Developer ID-signed, notarized DMG, manually or through the public Homebrew tap. Sparkle integration and a public HTTPS appcast remain planned; the app currently uses manual downloads or Homebrew for upgrades.

## Release Artifact

Run:

```sh
scripts/release-dmg.sh
```

The script archives the app, exports a Developer ID-signed `.app`, and creates:

```text
dist/ScreenshotMaxxing-<marketing-version>.dmg
```

The public DMG filename uses only the marketing version. The build number still lives in the app bundle as `CFBundleVersion` / `CURRENT_PROJECT_VERSION` and appears in release logs and release notes as `version (build)`.

To notarize and staple the DMG, first create a notarytool keychain profile:

```sh
xcrun notarytool store-credentials screenshotmaxxing-notary
```

Then run:

```sh
NOTARIZE=1 NOTARY_PROFILE=screenshotmaxxing-notary scripts/release-dmg.sh
```

The script uses [Config/ExportOptions-DeveloperID.plist](../Config/ExportOptions-DeveloperID.plist) for the Xcode export settings.

The default release path requires access to a `Developer ID Application` certificate. The script runs Xcode export with `-allowProvisioningUpdates` by default so Xcode can use cloud-managed Developer ID signing assets from your Apple Developer account.

In CI, the workflow imports a local Developer ID certificate and sets `ARCHIVE_CODE_SIGN_IDENTITY="Developer ID Application"` so the archive keeps hardened runtime signing before Xcode exports the notarizable app. It also sets `DMG_CODE_SIGN_IDENTITY="Developer ID Application"` so the notarized DMG has a primary signature that Gatekeeper can verify.

To check for a local keychain identity:

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

If this prints nothing, Xcode may still be able to export with a cloud-managed certificate. If export fails, create or refresh the certificate in Xcode:

```text
Xcode > Settings > Accounts > <Apple ID> > Manage Certificates... > + > Developer ID Application
```

This requires an Apple Developer Program membership with permission to create Developer ID certificates.

For a quick internal testing DMG without Developer ID export or notarization, run:

```sh
LOCAL_ONLY=1 scripts/release-dmg.sh
```

That DMG is useful for your own machines or technical testers, but macOS Gatekeeper may warn or block it for friends and coworkers.

## Local Development Builds

Debug builds use the bundle identifier `com.benmkramer.ScreenshotMaxxing.dev` and display as `ScreenshotMaxxing Dev` in macOS permission settings. Release builds keep `com.benmkramer.ScreenshotMaxxing`.

Keeping Debug and Release identities separate avoids mixing Screen Recording grants between an installed notarized app and branch builds from Xcode.

To reset both permission identities on a development machine, run:

```sh
scripts/reset-permissions.sh
```

## Release Automation

The release flow is controlled by version changes instead of every merge to `main`.

To prepare a release, run the `Prepare Release PR` workflow manually in GitHub Actions. Enter the new marketing version, for example `1.0.1`. The workflow runs:

```sh
scripts/prepare-release.sh <marketing-version> [build-number]
```

If no build number is provided, the script sets `CURRENT_PROJECT_VERSION` to the current maximum build number plus one. It also moves the current `CHANGELOG.md` `Unreleased` entries into a dated `## <version> - <date>` section and fails if there are no release notes to move. The workflow opens or updates a `release/v<version>` pull request with the Xcode project version and changelog changes.

When that pull request merges to `main`, the `Release DMG` workflow checks whether `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` changed in `ScreenshotMaxxing.xcodeproj/project.pbxproj`. If either changed, it builds the app, exports the Developer ID-signed app, notarizes and staples the DMG, validates the DMG, mounts it to verify the contained app signature and bundle versions, uploads the DMG as a workflow artifact, and creates or updates the matching GitHub Release tag.

Public release artifacts are named after `MARKETING_VERSION`, for example `ScreenshotMaxxing-1.0.1.dmg`. `CURRENT_PROJECT_VERSION` remains the monotonic build number inside the app bundle.

The `Release DMG` workflow can also be triggered manually from `main` with `publish_release` left disabled. That builds, signs, notarizes, validates, and uploads a workflow artifact without creating or updating a GitHub Release.

After a GitHub Release asset is uploaded, the workflow calls `Update Homebrew Cask`. Artifact-only manual builds do not update the tap. A tap update failure leaves the already published release available and marks the workflow failed so the maintainer can retry the tap update separately.

Required GitHub repository secrets:

```text
BUILD_CERTIFICATE_BASE64  Base64-encoded Developer ID Application .p12 certificate
P12_PASSWORD              Password for the .p12 certificate
KEYCHAIN_PASSWORD         Temporary CI keychain password
ASC_API_KEY_BASE64        Base64-encoded App Store Connect API key .p8 file
ASC_KEY_ID                App Store Connect API key ID
ASC_ISSUER_ID             App Store Connect issuer ID
```

Optional secret for the PR-preparation workflow:

```text
RELEASE_PR_TOKEN          Fine-grained PAT with contents and pull request access
```

The `Prepare Release PR` workflow creates pull requests from GitHub Actions. To allow that, either:

1. Enable `Settings > Actions > General > Workflow permissions > Allow GitHub Actions to create and approve pull requests`, or
2. Configure `RELEASE_PR_TOKEN`.

If `RELEASE_PR_TOKEN` is not configured, the workflow uses the default `GITHUB_TOKEN`. With the repository permission enabled, that is enough to create the release PR, but GitHub may suppress other workflows on the generated branch. Use `RELEASE_PR_TOKEN` if you want normal PR checks to run on release PRs.

On macOS, encode the certificate and API key for GitHub Secrets with:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i AuthKey_<key-id>.p8 | pbcopy
```

## Homebrew Distribution

The public [benmkramer/homebrew-tap](https://github.com/benmkramer/homebrew-tap) contains `Casks/screenshotmaxxing.rb`. Once that cask PR merges, users can install, launch, upgrade, and uninstall with:

```sh
brew install --cask benmkramer/tap/screenshotmaxxing
open -a ScreenshotMaxxing
brew update
brew upgrade --cask benmkramer/tap/screenshotmaxxing
brew uninstall --cask benmkramer/tap/screenshotmaxxing
```

Quit the app before upgrades or uninstall. Captures, SwiftData history, and preferences are preserved; there is no `zap` stanza. Existing manually installed app bundles must be moved out of `/Applications` before installation, without deleting user data.

The seed is stable `v2.0.9`, bundle build 14. Its public DMG is universal (`arm64` and `x86_64`) and its bundle declares macOS 26.2. Homebrew's supported dependency syntax expresses macOS by major release (`:tahoe`); the cask caveat states the exact 26.2 requirement, and macOS enforces the bundle minimum at launch. No quarantine removal, ad hoc signing, or Gatekeeper bypass is used.

The cask version is `<marketing-version>,<bundle-build>`, so build-only releases also produce Homebrew upgrades. Its versioned URL points at the published DMG. Do not replace an existing release with different bytes at the same marketing version and build: bump at least the build number. Otherwise existing Homebrew users need `brew reinstall --cask benmkramer/tap/screenshotmaxxing` to fetch the replacement.

### Channel And Verification Policy

The cask follows numeric stable tags, matching `scripts/set-release-version.sh`, and skips GitHub drafts and prereleases. The existing release-preparation script accepts numeric marketing versions only; this change does not add a prerelease publishing channel. Manually published prereleases remain available through GitHub Releases and are excluded from the stable cask.

`scripts/update-homebrew-cask.py` reads release metadata with GitHub's API, selects the exact final DMG asset, downloads its public URL without authentication, computes SHA-256, and compares the size and published digest when available. It verifies DMG integrity, its signature and stapled notarization ticket, Gatekeeper acceptance of the DMG and contained app, the app's Developer ID team/hardened runtime, bundle identity/version/build, and executable architectures. It derives the cask requirements from that bundle and fails on unsupported future macOS major versions until the Homebrew symbol mapping is updated.

The updater serializes tap writes, ignores older version/build pairs, and makes no commit when the cask already matches. Homebrew syntax, style, and strict online audits must pass before pushing a commit that stages only the app cask. Stable release assets remain hosted in this public app repository; no separate public artifact destination is needed.

### Maintainer Credential Setup

First inspect secret names, without retrieving values:

```sh
gh secret list --repo benmkramer/ScreenshotMaxxing
```

The existing six Apple signing/notarization secrets above remain required. Also configure `HOMEBREW_TAP_TOKEN` in **ScreenshotMaxxing**, with a fine-grained GitHub token whose repository access is restricted to **benmkramer/homebrew-tap**, and whose repository permission is **Contents: Read and write**. GitHub also grants mandatory metadata read access. No Pull requests or Workflows permission is needed because automation commits only the cask directly to tap `main`. That branch must permit the token owner to push; the initial cask and automation changes are reviewed in PRs.

Add or rotate the token through [Actions secrets](https://github.com/benmkramer/ScreenshotMaxxing/settings/secrets/actions), or use the interactive CLI prompt:

```sh
gh secret set HOMEBREW_TAP_TOKEN --repo benmkramer/ScreenshotMaxxing
```

Do not put the token in command arguments, source, logs, or chat. GitHub can list the secret's presence but cannot reveal or verify its contents/scope. Expiration, repository selection, and write access need to be checked by the owner or a real tap update.

Merge the tap cask PR before the app automation PR. After the app PR merges, future published stable releases update the tap automatically. To retry a failed update or sync an existing stable release without rebuilding, run **Update Homebrew Cask** on `main` with its tag:

```sh
gh workflow run update-homebrew.yml --repo benmkramer/ScreenshotMaxxing --ref main -f tag=v2.0.9
```

For local maintainer validation, use a clean tap feature-branch checkout:

```sh
python3 -m unittest discover -s scripts/tests -v
python3 scripts/update-homebrew-cask.py v2.0.9 /path/to/homebrew-tap
ruby -c /path/to/homebrew-tap/Casks/screenshotmaxxing.rb
brew style /path/to/homebrew-tap/Casks/screenshotmaxxing.rb
brew audit --cask --strict --online /path/to/homebrew-tap/Casks/screenshotmaxxing.rb
```

Installation/upgrade smoke tests should use a disposable macOS user or CI runner with no existing app and an isolated `--appdir`. Launch the official bundle only in a disposable user if validating startup could touch existing history/preferences. Do not use `--force`, `--adopt`, `--zap`, reset TCC, or alter the installed app during packaging tests on a user's working Mac.

The cask and validation commands follow the official [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook), [tap guide](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap), and [brew manual](https://docs.brew.sh/Manpage).

## Planned Sparkle Auto Updates

Use Sparkle 2. The release channel needs three things:

1. Sparkle added to the app target.
2. An HTTPS appcast URL embedded in the app as `SUFeedURL`.
3. A Sparkle EdDSA public key embedded in the app as `SUPublicEDKey`.

Recommended hosting for this repo:

```text
Sparkle updates: https://benmkramer.github.io/ScreenshotMaxxing/updates/
Manual downloads: GitHub Releases assets
```

Host the Sparkle appcast and Sparkle DMG archives in the same static HTTPS folder. GitHub Pages is a better appcast home than `raw.githubusercontent.com` because it is intended for stable public HTTPS hosting. GitHub Releases can still mirror the latest DMG for people installing manually.

## First Sparkle Setup

In Xcode:

1. Add the Sparkle Swift package:

   ```text
   https://github.com/sparkle-project/Sparkle
   ```

2. Link the `Sparkle` product to the `ScreenshotMaxxing` app target.
3. Add an updater controller in the app delegate and expose a `Check for Updates...` menu item.
4. Add these generated Info.plist values to the app target build settings:

   ```text
   INFOPLIST_KEY_SUFeedURL = https://benmkramer.github.io/ScreenshotMaxxing/updates/appcast.xml
   INFOPLIST_KEY_SUPublicEDKey = <Sparkle public EdDSA key>
   ```

Generate the EdDSA key pair with Sparkle's `generate_keys` tool. Keep the private key in the Keychain and commit only the public key.

## Updating the Appcast

Sparkle's `generate_appcast` can sign update archives and update the appcast. Once Sparkle is installed locally, the release script can copy the DMG into an updates folder and run the appcast generator. If Xcode has resolved the Sparkle package into the default derived data path, the script will find `generate_appcast` automatically:

```sh
SPARKLE_UPDATES_DIR=../screenshotmaxxing-pages/updates scripts/release-dmg.sh
```

If the Sparkle tool is elsewhere, pass it explicitly:

```sh
SPARKLE_UPDATES_DIR=../screenshotmaxxing-pages/updates \
SPARKLE_GENERATE_APPCAST=/path/to/Sparkle/bin/generate_appcast \
scripts/release-dmg.sh
```

Upload the whole updates directory, including `appcast.xml`, DMGs, release notes, and any generated delta files, to the public HTTPS directory referenced by `SUFeedURL`.

## Release Checklist

1. Run the `Prepare Release PR` workflow with the new marketing version, then merge the PR after CI passes.
2. Confirm the `Release DMG` workflow builds, exports, notarizes, staples, verifies the contained app, and uploads the DMG.
3. For manual local releases, build, export, notarize, and staple:

   ```sh
   NOTARIZE=1 NOTARY_PROFILE=screenshotmaxxing-notary scripts/release-dmg.sh
   ```

4. Confirm `Update Homebrew Cask` succeeds after publication; retry that workflow separately if needed.
5. Test `brew update` and `brew upgrade --cask benmkramer/tap/screenshotmaxxing` on a disposable installation.
6. When Sparkle is implemented, publish its updates directory and verify `Check for Updates...` from an older build.
