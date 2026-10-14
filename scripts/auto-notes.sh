#!/usr/bin/env bash
# Optional Stop hook. With CLAUDE_HANDOFF_AUTO_NOTES=N (default 0 = off), every N user
# turns it keeps Claude going for one more step: update the notes of the handoff.
# That step is a normal model turn and costs tokens, which is why it is off by default.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
n="$(int_setting "${CLAUDE_HANDOFF_AUTO_NOTES:-0}" 0)"
[ "$n" -gt 0 ] 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0
is_headless && exit 0

input="$(cat)"
printf '%s' "$input" | jq -e . >/dev/null 2>&1 || exit 0
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty')"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[ -f "$transcript" ] && [ -n "$sid" ] || exit 0
[ -n "$cwd" ] || cwd="$PWD"

count="$(jq -s -L "$HERE" 'include "scrub"; [ .[] | select(is_prompt) ] | length' "$transcript" 2>/dev/null)"
[ "$count" -gt 0 ] 2>/dev/null || exit 0

dir="$(handoff_dir "$cwd")"
state="$dir/.state/${sid:0:8}.auto-notes"
last=0; [ -f "$state" ] && last="$(int_setting "$(cat "$state")" 0)"
[ "$count" -ge $((last + n)) ] || exit 0
mkdir -p "$(dirname "$state")" && printf '%s' "$count" > "$state"

file="$(session_file_for "$dir" "$sid")"
[ -n "$file" ] || exit 0
root="$(root_of_file "$file")"
[ -n "$root" ] || exit 0
notes="$(notes_sidecar "$dir" "$root")"
[ -f "$notes" ] || notes_of "$file" > "$notes"
jq -nc --arg f "$notes" --arg n "$n" '{decision: "block",
  reason: ("Handoff plugin, scheduled notes update (every " + $n + " turns): rewrite " + $f + " with current notes (Goal, Done, In progress, Decisions, Rejected, Open questions, Next action with file:line or the exact command, Next steps, Gotchas; under 60 lines; plain markdown, no marker lines, never secrets). The handoff file shows it on the next render. Then stop without further commentary.")}'
exit 0
