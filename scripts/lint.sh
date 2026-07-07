#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/format.sh" --check
"$SCRIPT_DIR/validate-issue-template-yaml.sh"
