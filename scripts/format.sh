#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-format}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$REPO_ROOT/.swift-format"

usage() {
  cat <<USAGE
Usage: scripts/format.sh [format|--check]

Formats ScreenshotMaxxing Swift sources with swift-format.

Modes:
  format   Rewrite Swift files in place. This is the default.
  --check  Check formatting and style without rewriting files.
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

swift_format() {
  if command -v swift-format >/dev/null 2>&1; then
    swift-format "$@"
  elif xcrun --find swift-format >/dev/null 2>&1; then
    xcrun swift-format "$@"
  else
    die "missing swift-format; install Xcode's swift-format or add swift-format to PATH"
  fi
}

case "$MODE" in
  -h|--help|help)
    usage
    exit 0
    ;;
  format|--format)
    swift_format format \
      --configuration "$CONFIG_PATH" \
      --recursive \
      --parallel \
      --in-place \
      "$REPO_ROOT/ScreenshotMaxxing" \
      "$REPO_ROOT/ScreenshotMaxxingTests" \
      "$REPO_ROOT/ScreenshotMaxxingUITests"
    ;;
  --check|check|lint)
    swift_format lint \
      --configuration "$CONFIG_PATH" \
      --recursive \
      --parallel \
      --strict \
      "$REPO_ROOT/ScreenshotMaxxing" \
      "$REPO_ROOT/ScreenshotMaxxingTests" \
      "$REPO_ROOT/ScreenshotMaxxingUITests"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
