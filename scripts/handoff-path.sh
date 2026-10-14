#!/usr/bin/env bash
# Prints the handoff file of the CURRENT session (Claude Code exposes its id to shells
# as CLAUDE_CODE_SESSION_ID). Without that variable, falls back to the newest file.
#   --notes   prints the notes file of the session's thread instead (.state/<root8>.notes.md,
#             created from the current block of the handoff file if it does not exist yet)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
notes=0; [ "${1:-}" = "--notes" ] && { notes=1; shift; }
cwd="$(skill_project_dir "${1:-}")"
dir="$(handoff_dir "$cwd")"
sid="$(current_session_id)"
f=""
if [ -n "$sid" ]; then
  f="$(session_file_for "$dir" "$sid")"
  if [ -z "$f" ]; then
    echo "the current session (${sid:0:8}) has no handoff file yet in $dir; it is created by the Stop hook after Claude's first reply" >&2
    exit 1
  fi
else
  f="$(newest_session_file "$dir")"
  [ -n "$f" ] && echo "CLAUDE_CODE_SESSION_ID is not set; this is the newest file, not necessarily the current session's" >&2
fi
if [ -z "$f" ]; then
  echo "no handoff file yet in $dir (it is created by the Stop hook after Claude's first reply)" >&2
  exit 1
fi
if [ "$notes" = 1 ]; then
  root="$(root_of_file "$f")"
  [ -n "$root" ] || { echo "the file has no valid session id in its header" >&2; exit 1; }
  n="$(notes_sidecar "$dir" "$root")"
  if [ ! -f "$n" ]; then
    mkdir -p "$(dirname "$n")" 2>/dev/null || exit 1
    notes_of "$f" > "$n"
  fi
  printf '%s\n' "$n"
  exit 0
fi
printf '%s\n' "$f"
