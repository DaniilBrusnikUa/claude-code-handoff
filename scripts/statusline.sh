#!/usr/bin/env bash
# Status-bar segment: reads Claude Code's statusLine JSON on stdin, prints one line:
# the handoff file of this session, then zero-token nudges from fields only the status
# line receives (context_window.used_percentage, rate_limits.five_hour.used_percentage).
#   CLAUDE_HANDOFF_NUDGE_CONTEXT  context % from which "/handoff:notes" is suggested (70; 0 = off)
#   CLAUDE_HANDOFF_NUDGE_LIMIT    5-hour usage % from which it is suggested (90; 0 = off)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
input=""; [ -t 0 ] || input="$(cat)"
line="$(printf '%s' "$input" | "$HERE/handoff-status.sh" --short "$@")"
nc="$(int_setting "${CLAUDE_HANDOFF_NUDGE_CONTEXT:-}" 70)"
nl="$(int_setting "${CLAUDE_HANDOFF_NUDGE_LIMIT:-}" 90)"
ctx="$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty | floor' 2>/dev/null)"
lim="$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty | floor' 2>/dev/null)"
extra=""
if [ -n "$ctx" ]; then
  extra="$extra · ctx ${ctx}%"
  [ "$nc" -gt 0 ] && [ "$ctx" -ge "$nc" ] && extra="$extra → /handoff:notes before compaction"
fi
if [ -n "$lim" ] && [ "$nl" -gt 0 ] && [ "$lim" -ge "$nl" ]; then
  extra="$extra · 5h limit ${lim}% → /handoff:notes before the cutoff"
fi
printf '%s%s\n' "$line" "$extra"
