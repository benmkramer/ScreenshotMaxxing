#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="${PROJECT_FILE:-$REPO_ROOT/ScreenshotMaxxing.xcodeproj/project.pbxproj}"

usage() {
  cat <<USAGE
Usage: scripts/set-release-version.sh <marketing-version> [build-number]

Updates the Xcode project version settings used for release builds.

Arguments:
  marketing-version  CFBundleShortVersionString, for example 1.0.1
  build-number       Optional CFBundleVersion integer. Defaults to current max + 1.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

VERSION="${1:-}"
BUILD_NUMBER="${2:-}"

ruby - "$PROJECT_FILE" "$VERSION" "$BUILD_NUMBER" <<'RUBY'
project_file, version, build_number = ARGV

def die(message)
  warn "error: #{message}"
  exit 1
end

die "marketing-version is required" if version.nil? || version.empty?
die "invalid marketing version: #{version}" unless version.match?(/\A\d+(?:\.\d+){0,2}\z/)
die "invalid build number: #{build_number}" unless build_number.nil? || build_number.empty? || build_number.match?(/\A\d+\z/)
die "missing project file: #{project_file}" unless File.file?(project_file)

text = File.read(project_file)
marketing_settings = text.scan(/MARKETING_VERSION = [^;]+;/)
build_settings = text.scan(/CURRENT_PROJECT_VERSION = [^;]+;/)

die "no MARKETING_VERSION settings found in #{project_file}" if marketing_settings.empty?
die "no CURRENT_PROJECT_VERSION settings found in #{project_file}" if build_settings.empty?

if build_number.nil? || build_number.empty?
  current_builds = text.scan(/CURRENT_PROJECT_VERSION = ([0-9]+);/).flatten.map(&:to_i)
  die "cannot infer next build number from non-numeric CURRENT_PROJECT_VERSION settings" if current_builds.empty?

  build_number = (current_builds.max + 1).to_s
end

updated = text
  .gsub(/MARKETING_VERSION = [^;]+;/, "MARKETING_VERSION = #{version};")
  .gsub(/CURRENT_PROJECT_VERSION = [^;]+;/, "CURRENT_PROJECT_VERSION = #{build_number};")

File.write(project_file, updated)

puts "MARKETING_VERSION=#{version}"
puts "CURRENT_PROJECT_VERSION=#{build_number}"
puts "Updated #{marketing_settings.size} marketing version setting(s) and #{build_settings.size} build version setting(s)."
RUBY
