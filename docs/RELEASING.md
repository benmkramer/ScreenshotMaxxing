# Releasing ScreenshotMaxxing

ScreenshotMaxxing should be distributed as a Developer ID-signed, notarized DMG. Auto updates should use Sparkle with a public HTTPS appcast.

## Release Artifact

Run:

```sh
scripts/release-dmg.sh
```

The script archives the app, exports a Developer ID-signed `.app`, and creates:

```text
dist/ScreenshotMaxxing-<marketing-version>-<build>.dmg
```

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

## Auto Updates

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

1. Increment `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` in the Xcode project.
2. Build, export, notarize, and staple:

   ```sh
   NOTARIZE=1 NOTARY_PROFILE=screenshotmaxxing-notary scripts/release-dmg.sh
   ```

3. Upload the updates directory to GitHub Pages.
4. Optionally upload the same DMG to GitHub Releases for manual installs.
5. Launch an older installed build and use `Check for Updates...` to verify the update path.
