#!/usr/bin/env bash
# Prints the handoff file of the CURRENT session (Claude Code exposes its id to shells
# as CLAUDE_CODE_SESSION_ID). Without that variable, falls back to the newest file.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
cwd="${1:-$PWD}"
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
printf '%s\n' "$f"
