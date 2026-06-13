#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHANGELOG_FILE="${CHANGELOG_FILE:-$REPO_ROOT/CHANGELOG.md}"

usage() {
  cat <<USAGE
Usage: scripts/prepare-release.sh <marketing-version> [build-number]

Updates the Xcode project release version and moves CHANGELOG.md Unreleased
entries into a dated release section.

Arguments:
  marketing-version  CFBundleShortVersionString, for example 1.0.1
  build-number       Optional CFBundleVersion integer. Defaults to current max + 1.

Environment:
  RELEASE_DATE       Optional YYYY-MM-DD date for the changelog section.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

VERSION="${1:-}"
BUILD_NUMBER="${2:-}"
CHANGELOG_DIR="$(dirname "$CHANGELOG_FILE")"
CHANGELOG_TEMP="$(mktemp "$CHANGELOG_DIR/.prepare-release-changelog.XXXXXX")"
trap 'rm -f "$CHANGELOG_TEMP"' EXIT

ruby - "$CHANGELOG_FILE" "$VERSION" "${RELEASE_DATE:-}" "$CHANGELOG_TEMP" <<'RUBY'
require "date"

changelog_file, version, release_date, changelog_temp = ARGV

def die(message)
  warn "error: #{message}"
  exit 1
end

die "marketing-version is required" if version.nil? || version.empty?
die "invalid marketing version: #{version}" unless version.match?(/\A\d+(?:\.\d+){0,2}\z/)
die "missing changelog file: #{changelog_file}" unless File.file?(changelog_file)
die "missing changelog temp path" if changelog_temp.nil? || changelog_temp.empty?

if release_date.nil? || release_date.empty?
  release_date = Date.today.iso8601
else
  die "invalid release date: #{release_date}" unless release_date.match?(/\A\d{4}-\d{2}-\d{2}\z/)
  begin
    Date.iso8601(release_date)
  rescue Date::Error
    die "invalid release date: #{release_date}"
  end
end

text = File.read(changelog_file)
die "CHANGELOG.md already has a #{version} section" if text.match?(/^##\s+#{Regexp.escape(version)}(?:\s+-\s+.*)?$/)

die "CHANGELOG.md is missing a ## Unreleased section" unless text.match?(/^## Unreleased\s*$/)

unreleased_match = text.match(/^## Unreleased\s*\n(?<body>.*?)(?=^##\s+)/m)
die "CHANGELOG.md Unreleased section must be followed by another ## section" unless unreleased_match

body = unreleased_match[:body]
entries = body.lines.drop_while { |line| line.strip.empty? }
entries.pop while entries.any? && entries.last.strip.empty?

die "CHANGELOG.md Unreleased section has no release notes" if entries.empty?
die "CHANGELOG.md Unreleased section has no bullet entries" unless entries.any? { |line| line.start_with?("- ") }

release_section = "## Unreleased\n\n## #{version} - #{release_date}\n\n#{entries.join}\n"
updated = text.sub(/^## Unreleased\s*\n.*?(?=^##\s+)/m, release_section)

File.write(changelog_temp, updated)

puts "CHANGELOG_VERSION=#{version}"
puts "CHANGELOG_DATE=#{release_date}"
puts "Prepared #{changelog_file}"
RUBY

"$SCRIPT_DIR/set-release-version.sh" "$VERSION" "$BUILD_NUMBER"
mv "$CHANGELOG_TEMP" "$CHANGELOG_FILE"
trap - EXIT

printf 'Updated %s\n' "$CHANGELOG_FILE"
