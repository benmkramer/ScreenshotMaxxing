#!/usr/bin/env bash
set -euo pipefail

# Startup may initialize SwiftData/preferences. Only CI's disposable macOS
# account may use --launch; local packaging tests never launch the official ID.
if [[ "${1:-}" == "--launch" && "${GITHUB_ACTIONS:-}" != "true" ]]; then
  echo "Launch testing requires a disposable GitHub Actions macOS account." >&2
  exit 1
fi

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ANALYTICS=1
TOKEN="benmkramer/tap/screenshotmaxxing"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/screenshotmaxxing-homebrew-test.XXXXXX")"
APP_DIR="$TEST_ROOT/Applications"
APP_PATH="$APP_DIR/ScreenshotMaxxing.app"
LAUNCH_PID=""
INSTALLED=0
DATA_SENTINEL=""
PREFERENCE_KEY="HomebrewPackagingTest"

if brew list --cask "$TOKEN" >/dev/null 2>&1; then
  echo "Refusing to change an existing Homebrew ScreenshotMaxxing installation." >&2
  exit 1
fi
if [[ "${1:-}" == "--launch" ]] && {
  [[ -e /Applications/ScreenshotMaxxing.app ]] || pgrep -x ScreenshotMaxxing >/dev/null;
}; then
  echo "Refusing launch testing while another official installation/process exists." >&2
  exit 1
fi

brew tap benmkramer/tap
TAP_PATH="$(brew --repository benmkramer/tap)"
CASK_PATH="$TAP_PATH/Casks/screenshotmaxxing.rb"
HAD_CASK=0
if [[ -f "$CASK_PATH" ]]; then
  cp "$CASK_PATH" "$TEST_ROOT/original-cask.rb"
  HAD_CASK=1
fi

cleanup() {
  if [[ -n "$LAUNCH_PID" ]] && kill -0 "$LAUNCH_PID" 2>/dev/null; then
    kill "$LAUNCH_PID" || true
  fi
  if [[ "$INSTALLED" == "1" ]]; then
    brew uninstall --cask "$TOKEN" || true
  fi
  if [[ "$HAD_CASK" == "1" ]]; then
    cp "$TEST_ROOT/original-cask.rb" "$CASK_PATH"
  else
    rm -f "$CASK_PATH"
  fi
  if [[ -n "$DATA_SENTINEL" ]]; then
    rm -f "$DATA_SENTINEL"
    defaults delete com.benmkramer.ScreenshotMaxxing "$PREFERENCE_KEY" || true
  fi
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$APP_DIR"
if [[ "${1:-}" == "--launch" ]]; then
  DATA_SENTINEL="$HOME/Library/Application Support/ScreenshotMaxxing/Captures/homebrew-packaging-test.txt"
  mkdir -p "$(dirname "$DATA_SENTINEL")"
  printf 'preserve capture data\n' > "$DATA_SENTINEL"
  defaults write com.benmkramer.ScreenshotMaxxing "$PREFERENCE_KEY" -string preserve
fi
# Keep a real earlier release for the upgrade test. The updater derives its
# checksum, build number, and requirements instead of hard-coding them here.
python3 "$SCRIPT_DIR/update-homebrew-cask.py" v2.0.8 "$TEST_ROOT/old-tap"
mkdir -p "$(dirname "$CASK_PATH")"
cp "$TEST_ROOT/old-tap/Casks/screenshotmaxxing.rb" "$CASK_PATH"
brew install --cask --appdir="$APP_DIR" "$TOKEN"
INSTALLED=1
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")" == "2.0.8"

TAG="$(gh release view --repo benmkramer/ScreenshotMaxxing --json tagName --jq .tagName)"
python3 "$SCRIPT_DIR/update-homebrew-cask.py" "$TAG" "$TAP_PATH"
ruby -c "$CASK_PATH"
brew style --cask "$TOKEN"
brew audit --cask --strict --online "$TOKEN"
brew upgrade --cask --appdir="$APP_DIR" "$TOKEN"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")" == "${TAG#v}"
if [[ -n "$DATA_SENTINEL" ]]; then
  test "$(cat "$DATA_SENTINEL")" == "preserve capture data"
  test "$(defaults read com.benmkramer.ScreenshotMaxxing "$PREFERENCE_KEY")" == "preserve"
fi
codesign --verify --deep --strict "$APP_PATH"
spctl --assess --verbose=2 --type execute "$APP_PATH"
# Homebrew's default quarantine must remain in place.
xattr -p com.apple.quarantine "$APP_PATH"

if [[ "${1:-}" == "--launch" ]]; then
  open -n "$APP_PATH"
  for attempt in 1 2 3 4 5; do
    LAUNCH_PID="$(pgrep -f "^$APP_PATH/Contents/MacOS/ScreenshotMaxxing$" || true)"
    [[ -n "$LAUNCH_PID" ]] && break
    sleep 1
  done
  test -n "$LAUNCH_PID"
  sleep 2
  kill -0 "$LAUNCH_PID"
  echo "Official quarantined app launched and stayed running."
  kill "$LAUNCH_PID"
  LAUNCH_PID=""
fi

brew uninstall --cask "$TOKEN"
INSTALLED=0
test ! -e "$APP_PATH"
if [[ -n "$DATA_SENTINEL" ]]; then
  test "$(cat "$DATA_SENTINEL")" == "preserve capture data"
  test "$(defaults read com.benmkramer.ScreenshotMaxxing "$PREFERENCE_KEY")" == "preserve"
fi
echo "Public artifact verification, install, upgrade, and normal uninstall passed."
