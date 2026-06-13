#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ScreenshotMaxxing"
SCHEME="ScreenshotMaxxing"
CONFIGURATION="${CONFIGURATION:-Debug}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$REPO_ROOT/build/DerivedData/BuildAndRun}"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
MODE="${1:-run}"

usage() {
  cat <<USAGE
Usage: scripts/build-and-run.sh [run|--verify|--logs]

Builds the Debug app, stops any running $APP_NAME process, and launches the
fresh app bundle with /usr/bin/open -n.

Environment:
  CONFIGURATION=<name>        Defaults to Debug.
  DERIVED_DATA_PATH=<path>    Defaults to build/DerivedData/BuildAndRun.
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

stop_running_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

resolve_app_bundle() {
  if [[ -d "$APP_BUNDLE" ]]; then
    printf '%s\n' "$APP_BUNDLE"
    return
  fi

  local found_app
  found_app="$(find "$DERIVED_DATA_PATH/Build/Products" -maxdepth 3 -path "*/$APP_NAME.app" -type d 2>/dev/null | head -n 1 || true)"
  [[ -n "$found_app" ]] || die "expected built app at $APP_BUNDLE"
  printf '%s\n' "$found_app"
}

build_app() {
  xcodebuild build \
    -project "$REPO_ROOT/$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH"
}

open_app() {
  local app_bundle="$1"
  /usr/bin/open -n "$app_bundle"
}

case "$MODE" in
  -h|--help|help)
    usage
    exit 0
    ;;
  run|--verify|verify|--logs|logs)
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

require_command xcodebuild
require_command /usr/bin/open
require_command pkill

stop_running_app
build_app
BUILT_APP="$(resolve_app_bundle)"
open_app "$BUILT_APP"

case "$MODE" in
  --verify|verify)
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null || die "$APP_NAME did not appear to be running after launch"
    printf 'Launched %s\n' "$BUILT_APP"
    ;;
  --logs|logs)
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  run)
    printf 'Launched %s\n' "$BUILT_APP"
    ;;
esac
