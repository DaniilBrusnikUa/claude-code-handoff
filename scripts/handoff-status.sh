#!/usr/bin/env bash
# Prints where the current session writes: file, thread, status, open sessions.
#   --short   one line for a status bar
# Session id: CLAUDE_CODE_SESSION_ID, or the "session_id" of a JSON object on stdin
# (the shape Claude Code hands to statusLine commands), or $1.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
short=0; [ "${1:-}" = "--short" ] && { short=1; shift; }
sid="${1:-$(current_session_id)}"
cwd="${2:-}"
if [ -z "$sid" ] && [ ! -t 0 ]; then
  input="$(cat)"
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
  c="$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null)"
  [ -n "$c" ] && cwd="$c"
fi
cwd="$(skill_project_dir "$cwd")"
dir="$(handoff_dir "$cwd")"
f=""; [ -n "$sid" ] && f="$(session_file_for "$dir" "$sid")"
if [ -z "$f" ]; then
  [ "$short" = 1 ] && printf '📝 handoff: no file yet (written after the first reply)\n' || printf 'No handoff file for this session yet in %s; it is written after the first reply.\n' "$dir"
  exit 0
fi
root="$(root_of_file "$f")"
n=1; [ -n "$root" ] && n="$(thread_members "$dir" "$root" | grep -c .)"
opens=""; [ -n "$root" ] && opens="$(open_members "$dir" "$root" | tr '\n' ' ' | sed 's/ $//')"
ic="$(status_icon "$f")"
if [ "$short" = 1 ]; then
  printf '📝 %s %s%s · %s\n' "${ic:-⚪}" "$(basename "$f")" "$([ "$n" -gt 1 ] && printf ' · thread %s' "$n")" "$f"
else
  printf 'File:     %s\nThread:   %s (%s session(s))\nStatus:   %s\nOpen now: %s\nNotes:    %s\nDir:      %s\n' "$f" "${root:0:8}" "$n" "$(header_field "$f" Status)" "${opens:-none}" "$(notes_sidecar "$dir" "${root:-00000000}")" "$dir"
fi
