#!/usr/bin/env bash
# Status-bar segment: reads Claude Code's statusLine JSON on stdin, prints one line:
#   handoff ● <title> · ctx 41%                    normal
#   handoff ● <title> · ctx 72% → /handoff:notes   context high: write notes before compaction
#   … · 5h 83% → /handoff:notes | · 5h 96% → notes now | · 7d 91%
#   handoff ○ after first reply                     no file yet
# The percentages reach only the status line (never hooks), so this is the one place the
# plugin can warn without spending a token.
#   CLAUDE_HANDOFF_NUDGE_CONTEXT     context % from which notes are suggested (70; 0 = off)
#   CLAUDE_HANDOFF_NUDGE_LIMIT       5-hour usage % from which they are suggested (80; 0 = off)
#   CLAUDE_HANDOFF_NUDGE_LIMIT_HARD  5-hour usage % from which it says "notes now" (95)
#   CLAUDE_HANDOFF_NUDGE_WEEK        7-day usage % shown from (90; 0 = off)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
command -v jq >/dev/null 2>&1 || { printf 'handoff: jq missing\n'; exit 0; }
input=""; [ -t 0 ] || input="$(cat)"
line="$(printf '%s' "$input" | "$HERE/handoff-status.sh" --short "$@")"
nc="$(int_setting "${CLAUDE_HANDOFF_NUDGE_CONTEXT:-}" 70)"
nl="$(int_setting "${CLAUDE_HANDOFF_NUDGE_LIMIT:-}" 80)"
nh="$(int_setting "${CLAUDE_HANDOFF_NUDGE_LIMIT_HARD:-}" 95)"
nw="$(int_setting "${CLAUDE_HANDOFF_NUDGE_WEEK:-}" 90)"
ctx="$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty | floor' 2>/dev/null)"
lim="$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty | floor' 2>/dev/null)"
wk="$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty | floor' 2>/dev/null)"
extra=""
if [ -n "$ctx" ]; then
  extra="$extra · ctx ${ctx}%"
  [ "$nc" -gt 0 ] && [ "$ctx" -ge "$nc" ] && extra="$extra → /handoff:notes"
fi
if [ -n "$lim" ] && [ "$nl" -gt 0 ] && [ "$lim" -ge "$nl" ]; then
  if [ "$nh" -gt 0 ] && [ "$lim" -ge "$nh" ]; then extra="$extra · 5h ${lim}% → notes now"
  else extra="$extra · 5h ${lim}% → /handoff:notes"; fi
fi
if [ -n "$wk" ] && [ "$nw" -gt 0 ] && [ "$wk" -ge "$nw" ]; then
  extra="$extra · 7d ${wk}%"
fi
printf '%s%s\n' "$line" "$extra"
