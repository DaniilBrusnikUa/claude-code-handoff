#!/usr/bin/env bash
# Opens the current session's handoff file in the default application (macOS `open`,
# Linux `xdg-open`); otherwise prints the path.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
f="$("$HERE/handoff-path.sh" "${1:-$PWD}")" || exit 1
if command -v open >/dev/null 2>&1 && [ "$(uname)" = "Darwin" ]; then open "$f"
elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$f" >/dev/null 2>&1
fi
printf '%s\n' "$f"
