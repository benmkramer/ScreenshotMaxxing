#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

shopt -s nullglob
issue_templates=(.github/ISSUE_TEMPLATE/*.yml .github/ISSUE_TEMPLATE/*.yaml)
shopt -u nullglob

if ((${#issue_templates[@]} == 0)); then
  exit 0
fi

ruby -ryaml -e '
valid = true

ARGV.each do |path|
  begin
    YAML.load_file(path)
  rescue Psych::SyntaxError => error
    warn "error: invalid YAML in #{path}: #{error.problem} at line #{error.line}, column #{error.column}"
    valid = false
  rescue StandardError => error
    warn "error: could not parse YAML in #{path}: #{error.message}"
    valid = false
  end
end

exit(valid ? 0 : 1)
' "${issue_templates[@]}"
