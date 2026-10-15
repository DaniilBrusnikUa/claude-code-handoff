#!/usr/bin/env bash
# Optional Stop hook. CLAUDE_HANDOFF_AUTO_NOTES (default 0 = off) keeps Claude going for one
# more step, updating the notes of the handoff:
#   context   when the context crosses 60% and then 85% of the window, once per threshold,
#             re-armed after a compaction (CLAUDE_HANDOFF_AUTO_NOTES_AT="60,85",
#             CLAUDE_HANDOFF_CONTEXT_WINDOW=200000). The notes are fresh when compaction comes.
#   N         every N user turns.
# That step is a normal model turn and costs tokens, which is why it is off by default.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
mode="$(lower "${CLAUDE_HANDOFF_AUTO_NOTES:-0}")"
n=0
if [ "$mode" != "context" ]; then
  n="$(int_setting "$mode" 0)"
  [ "$n" -gt 0 ] 2>/dev/null || exit 0
fi
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

dir="$(handoff_dir "$cwd")"
state="$dir/.state/${sid:0:8}.auto-notes"
last=0; [ -f "$state" ] && last="$(int_setting "$(cat "$state")" 0)"
why=""
if [ "$mode" = "context" ]; then
  # Context of the last request = what the next one re-sends; percent of the model's window.
  # Window: the setting, else derived from the transcript (a request above 200k means the
  # model runs with the 1M window).
  read -r ctx maxctx <<< "$(jq -rs '[ .[] | select(.type == "assistant" and .message.usage != null) | .message.usage
        | ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)) ]
        | "\(last // 0) \(max // 0)"' "$transcript" 2>/dev/null)"
  window="$(int_setting "${CLAUDE_HANDOFF_CONTEXT_WINDOW:-}" 0)"
  if [ "$window" -le 0 ]; then
    window=200000; [ "${maxctx:-0}" -gt 200000 ] 2>/dev/null && window=1000000
  fi
  [ "$ctx" -gt 0 ] 2>/dev/null || exit 0
  pct=$((ctx * 100 / window))
  first=""; hit=""
  for t in $(printf '%s' "${CLAUDE_HANDOFF_AUTO_NOTES_AT:-60,85}" | tr ',' ' '); do
    t="$(int_setting "$t" 0)"; [ "$t" -gt 0 ] || continue
    [ -n "$first" ] || first="$t"
    [ "$pct" -ge "$t" ] && hit="$t"
  done
  # Below the first threshold again (compaction happened): re-arm.
  if [ -n "$first" ] && [ "$pct" -lt "$first" ] && [ "$last" -ne 0 ]; then
    mkdir -p "$(dirname "$state")" && printf '0' > "$state"
  fi
  [ -n "$hit" ] && [ "$hit" -gt "$last" ] || exit 0
  mkdir -p "$(dirname "$state")" && printf '%s' "$hit" > "$state"
  why="context at ${pct}% of the window, compaction is near"
else
  count="$(jq -s -L "$HERE" 'include "scrub"; [ .[] | select(is_prompt) ] | length' "$transcript" 2>/dev/null)"
  [ "$count" -gt 0 ] 2>/dev/null || exit 0
  [ "$count" -ge $((last + n)) ] || exit 0
  mkdir -p "$(dirname "$state")" && printf '%s' "$count" > "$state"
  why="every $n turns"
fi

file="$(session_file_for "$dir" "$sid")"
[ -n "$file" ] || exit 0
root="$(root_of_file "$file")"
[ -n "$root" ] || exit 0
notes="$(notes_sidecar "$dir" "$root")"
[ -f "$notes" ] || notes_of "$file" > "$notes"
jq -nc --arg f "$notes" --arg w "$why" '{decision: "block",
  reason: ("Handoff plugin, notes update (" + $w + "): rewrite " + $f + " with current notes (Goal, Done, In progress, Decisions, Rejected, Open questions, Next action with file:line or the exact command, Next steps, Gotchas; under 60 lines; plain markdown, no marker lines, never secrets). The handoff file shows it on the next render. Then stop without further commentary.")}'
exit 0
