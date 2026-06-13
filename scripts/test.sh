#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ScreenshotMaxxing"
SCHEME="ScreenshotMaxxing"
CONFIGURATION="${CONFIGURATION:-Debug}"
MODE="${1:-unit}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$REPO_ROOT/build/DerivedData/Test}"

usage() {
  cat <<USAGE
Usage: scripts/test.sh [unit|--all]

Runs ScreenshotMaxxing tests with xcodebuild.

Modes:
  unit      Run the deterministic unit test target. This is the default.
  --all     Run the full scheme, including UI tests.

Environment:
  CONFIGURATION=<name>        Defaults to Debug.
  DERIVED_DATA_PATH=<path>    Defaults to build/DerivedData/Test.
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

case "$MODE" in
  -h|--help|help)
    usage
    exit 0
    ;;
  unit|--unit)
    ONLY_TESTING_TARGET="ScreenshotMaxxingTests"
    ;;
  --all|all)
    ONLY_TESTING_TARGET=""
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

require_command xcodebuild

test_args=(
  test
  -project "$REPO_ROOT/$APP_NAME.xcodeproj"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination 'platform=macOS'
  -derivedDataPath "$DERIVED_DATA_PATH"
  CODE_SIGNING_ALLOWED=NO
)

if [[ -n "$ONLY_TESTING_TARGET" ]]; then
  test_args+=("-only-testing:$ONLY_TESTING_TARGET")
fi

xcodebuild "${test_args[@]}"
