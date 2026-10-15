#!/usr/bin/env bash
# Prints where the current session writes: file, thread, status, open sessions.
#   --short   one segment for a status bar: "handoff ● <title>" / "handoff ○ after first reply"
# Session id: the "session_id" of a JSON object on stdin (the shape Claude Code hands to
# statusLine commands; it wins over the environment, which can be stale in a reused shell),
# else CLAUDE_CODE_SESSION_ID, else $1.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
command -v jq >/dev/null 2>&1 || { printf 'handoff: jq missing\n'; exit 0; }
short=0; [ "${1:-}" = "--short" ] && { short=1; shift; }
sid="${1:-}"
cwd="${2:-}"
if [ ! -t 0 ]; then
  input="$(cat)"
  jsid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
  [ -n "$jsid" ] && sid="$jsid"
  c="$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null)"
  [ -n "$c" ] && [ -z "$cwd" ] && cwd="$c"
fi
[ -n "$sid" ] || sid="$(current_session_id)"
cwd="$(skill_project_dir "$cwd")"
dir="$(handoff_dir "$cwd")"
f=""; [ -n "$sid" ] && f="$(session_file_for "$dir" "$sid")"
if [ -z "$f" ]; then
  [ "$short" = 1 ] && printf 'handoff ○ after first reply\n' || printf 'No handoff file for this session yet in %s; it is written after the first reply.\n' "$dir"
  exit 0
fi
root="$(root_of_file "$f")"
n=1; [ -n "$root" ] && n="$(thread_members "$dir" "$root" | grep -c .)"
opens=""; [ -n "$root" ] && opens="$(open_members "$dir" "$root" | tr '\n' ' ' | sed 's/ $//')"
if [ "$short" = 1 ]; then
  loc="$(utf8_locale)"; [ -n "$loc" ] && export LC_ALL="$loc"
  t="$(file_title "$f")"; t="${t:0:28}"
  printf 'handoff ● %s%s\n' "$t" "$([ "$n" -gt 1 ] && printf ' (+%s)' $((n - 1)))"
else
  printf 'File:     %s\nThread:   %s (%s session(s))\nStatus:   %s\nOpen now: %s\nNotes:    %s\nDir:      %s\n' "$f" "${root:0:8}" "$n" "$(header_field "$f" Status)" "${opens:-none}" "$(notes_sidecar "$dir" "${root:-00000000}")" "$dir"
fi
