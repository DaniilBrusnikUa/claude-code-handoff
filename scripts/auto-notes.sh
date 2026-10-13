#!/usr/bin/env bash
# Optional Stop hook. With CLAUDE_HANDOFF_AUTO_NOTES=N (default 0 = off), every N user
# turns it keeps Claude going for one more step: update the notes block of the handoff.
# That step is a normal model turn and costs tokens, which is why it is off by default.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
n="${CLAUDE_HANDOFF_AUTO_NOTES:-0}"
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

count="$(jq -s '[ .[] | select(.type == "user" and .isMeta != true and .isCompactSummary != true and (.message.content | type) == "string"
                        and (.message.content | test("^\\s*<(command-name|command-message|local-command)") | not)
                        and (.message.content | test("^\\s*/[A-Za-z][A-Za-z0-9:_-]*\\s*$") | not)) ] | length' "$transcript" 2>/dev/null)"
[ "$count" -gt 0 ] 2>/dev/null || exit 0

dir="$(handoff_dir "$cwd")"
state="$dir/.state/${sid:0:8}.auto-notes"
last=0; [ -f "$state" ] && last="$(cat "$state")"
[ "$count" -ge $((last + n)) ] || exit 0
mkdir -p "$(dirname "$state")" && printf '%s' "$count" > "$state"

file="$(session_file_for "$dir" "$sid")"
[ -n "$file" ] || exit 0
jq -nc --arg f "$file" '{decision: "block",
  reason: ("Handoff plugin, scheduled notes update (every " + env.CLAUDE_HANDOFF_AUTO_NOTES + " turns): in " + $f + " replace the block between <!-- handoff:notes:start --> and <!-- handoff:notes:end --> with current notes (Goal, State, Decisions, Rejected, Open questions, Next steps, Gotchas; under 60 lines; keep the markers), copy the file over LATEST.md in the same directory, then stop without further commentary.")}'
exit 0
