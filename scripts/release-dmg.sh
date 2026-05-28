#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ScreenshotMaxxing"
SCHEME="ScreenshotMaxxing"
CONFIGURATION="Release"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/private/tmp/ScreenshotMaxxingDerivedData}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_DIR/$APP_NAME.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$BUILD_DIR/export}"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$REPO_ROOT/Config/ExportOptions-DeveloperID.plist}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
LOCAL_ONLY="${LOCAL_ONLY:-0}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-1}"
ARCHIVE_CODE_SIGN_IDENTITY="${ARCHIVE_CODE_SIGN_IDENTITY:-}"
DMG_CODE_SIGN_IDENTITY="${DMG_CODE_SIGN_IDENTITY:-}"
SPARKLE_UPDATES_DIR="${SPARKLE_UPDATES_DIR:-}"
SPARKLE_GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-}"
DEFAULT_SPARKLE_GENERATE_APPCAST="$DERIVED_DATA_PATH/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"

usage() {
  cat <<USAGE
Usage: scripts/release-dmg.sh

Builds a Developer ID export and creates dist/$APP_NAME-<marketing-version>-<build>.dmg.

Environment:
  DERIVED_DATA_PATH           Defaults to /private/tmp/ScreenshotMaxxingDerivedData
  ALLOW_PROVISIONING_UPDATES=0
                              Do not let Xcode create/download signing assets during export.
                              Defaults to 1 to support cloud-managed Developer ID certificates.
  LOCAL_ONLY=1                Skip Developer ID export and package the archived app directly.
                              This creates a DMG for local/internal testing, not a notarizable release.
  NOTARIZE=1                  Submit and staple the DMG with xcrun notarytool
  NOTARY_PROFILE=<profile>    Keychain profile created with xcrun notarytool store-credentials
  ARCHIVE_CODE_SIGN_IDENTITY=<identity>
                              Override archive signing, for example "Developer ID Application".
  DMG_CODE_SIGN_IDENTITY=<identity>
                              Sign the DMG before notarization, for example "Developer ID Application".
  SPARKLE_UPDATES_DIR=<dir>   Copy the DMG into a Sparkle updates directory
  SPARKLE_GENERATE_APPCAST=<path>
                              Run Sparkle's generate_appcast against SPARKLE_UPDATES_DIR.
                              Defaults to Xcode's Sparkle package artifact path when present.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_command xcodebuild
require_command hdiutil
require_command /usr/libexec/PlistBuddy
require_command ditto

if [[ "$LOCAL_ONLY" == "1" && "$NOTARIZE" == "1" ]]; then
  die "LOCAL_ONLY=1 cannot be notarized. Install a Developer ID Application certificate and run without LOCAL_ONLY for notarized releases."
fi

if [[ "$NOTARIZE" == "1" ]]; then
  require_command ruby
fi

if [[ -n "$DMG_CODE_SIGN_IDENTITY" ]]; then
  require_command codesign
fi

if [[ "$LOCAL_ONLY" != "1" && "$ALLOW_PROVISIONING_UPDATES" != "1" ]]; then
  if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
    die "No local Developer ID Application signing identity found. Either create one in Xcode, or run with ALLOW_PROVISIONING_UPDATES=1 so Xcode can use cloud-managed signing assets."
  fi
fi

mkdir -p "$BUILD_DIR" "$DIST_DIR"
rm -rf "$EXPORT_PATH"

printf 'Archiving %s...\n' "$APP_NAME"
archive_args=(
  -project "$REPO_ROOT/$APP_NAME.xcodeproj"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -archivePath "$ARCHIVE_PATH"
)

if [[ "$LOCAL_ONLY" != "1" && -n "$ARCHIVE_CODE_SIGN_IDENTITY" ]]; then
  archive_args+=(
    CODE_SIGN_IDENTITY="$ARCHIVE_CODE_SIGN_IDENTITY"
    CODE_SIGN_STYLE=Manual
  )
fi

xcodebuild "${archive_args[@]}" archive

if [[ "$LOCAL_ONLY" == "1" ]]; then
  printf 'Skipping Developer ID export because LOCAL_ONLY=1...\n'
  APP_BUNDLE="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
else
  printf 'Exporting Developer ID app...\n'
  export_args=(
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
  )

  if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
    export_args+=(-allowProvisioningUpdates)
  fi

  xcodebuild "${export_args[@]}"

  APP_BUNDLE="$EXPORT_PATH/$APP_NAME.app"
fi

[[ -d "$APP_BUNDLE" ]] || die "expected exported app at $APP_BUNDLE"

INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
DMG_NAME="$APP_NAME-$MARKETING_VERSION-$BUILD_VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
DMG_ROOT="$BUILD_DIR/dmg-root"

printf 'Creating %s...\n' "$DMG_PATH"
rm -rf "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$DMG_ROOT"
ditto "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "$DMG_CODE_SIGN_IDENTITY" ]]; then
  printf 'Signing %s...\n' "$DMG_NAME"
  codesign --force --sign "$DMG_CODE_SIGN_IDENTITY" --timestamp "$DMG_PATH"
fi

if [[ "$NOTARIZE" == "1" ]]; then
  [[ -n "$NOTARY_PROFILE" ]] || die "NOTARY_PROFILE is required when NOTARIZE=1"
  printf 'Submitting %s for notarization...\n' "$DMG_NAME"
  NOTARY_OUTPUT="$BUILD_DIR/notary-submit.json"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$NOTARY_OUTPUT"
  cat "$NOTARY_OUTPUT"

  NOTARY_STATUS="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).fetch("status", "")' "$NOTARY_OUTPUT")"
  NOTARY_ID="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).fetch("id", "")' "$NOTARY_OUTPUT")"

  if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
    if [[ -n "$NOTARY_ID" ]]; then
      xcrun notarytool log "$NOTARY_ID" --keychain-profile "$NOTARY_PROFILE" || true
    fi
    die "notarization failed with status: ${NOTARY_STATUS:-unknown}"
  fi

  printf 'Stapling notarization ticket...\n'
  xcrun stapler staple "$DMG_PATH"
fi

if [[ -n "$SPARKLE_UPDATES_DIR" ]]; then
  mkdir -p "$SPARKLE_UPDATES_DIR"
  cp "$DMG_PATH" "$SPARKLE_UPDATES_DIR/$DMG_NAME"

  if [[ -z "$SPARKLE_GENERATE_APPCAST" && -x "$DEFAULT_SPARKLE_GENERATE_APPCAST" ]]; then
    SPARKLE_GENERATE_APPCAST="$DEFAULT_SPARKLE_GENERATE_APPCAST"
  fi

  if [[ -n "$SPARKLE_GENERATE_APPCAST" ]]; then
    [[ -x "$SPARKLE_GENERATE_APPCAST" ]] || die "SPARKLE_GENERATE_APPCAST is not executable: $SPARKLE_GENERATE_APPCAST"
    printf 'Generating Sparkle appcast in %s...\n' "$SPARKLE_UPDATES_DIR"
    "$SPARKLE_GENERATE_APPCAST" "$SPARKLE_UPDATES_DIR"
  fi
fi

printf 'Done: %s\n' "$DMG_PATH"
