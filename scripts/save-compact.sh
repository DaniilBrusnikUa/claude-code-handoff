#!/usr/bin/env bash
# PostCompact hook. Claude Code hands us the summary it just generated (already
# paid for); we store it so the handoff file can carry it. No model calls.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
command -v jq >/dev/null 2>&1 || exit 0
is_headless && exit 0

input="$(cat)"
printf '%s' "$input" | jq -e . >/dev/null 2>&1 || exit 0
sid="$(printf '%s' "$input" | jq -r '.session_id // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
trigger="$(printf '%s' "$input" | jq -r '.trigger // "unknown"')"
# Claude Code wraps the summary in <summary> tags and uses its own "## " headings; strip the
# wrapper and demote headings so they cannot be mistaken for the handoff file's sections.
summary="$(printf '%s' "$input" | jq -r -L "$HERE" 'include "scrub"; .compact_summary // empty | scrub' \
  | sed -e 's#^[[:space:]]*</\{0,1\}summary>[[:space:]]*$##' -e 's/^#\{1,3\} /#### /' | cat -s | sed -e '/./,$!d')"
[ -n "$sid" ] && [ -n "$summary" ] || exit 0
[ -n "$cwd" ] || cwd="$PWD"

dir="$(handoff_dir "$cwd")"
side="$(compact_sidecar "$dir" "$sid")"
mkdir -p "$(dirname "$side")" 2>/dev/null || exit 0
{
  printf '### %s (%s)\n\n' "$(date '+%Y-%m-%d %H:%M')" "$trigger"
  printf '%s\n\n' "$summary"
} >> "$side"

# Refresh the session file right away so the summary is visible without waiting for the next Stop.
printf '%s' "$input" | "$HERE/save-handoff.sh"
exit 0
