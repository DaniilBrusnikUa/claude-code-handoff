#!/usr/bin/env bash
# Prints one handoff file: by number from handoff-list.sh, by session id, or by part of the
# name. No argument: the newest one.
#   --adopt   the current session joins that file's thread: from now on its hooks write into
#             this file (together with the earlier sessions), and it gets no file of its own.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
adopt=0
[ "${1:-}" = "--adopt" ] && { adopt=1; shift; }
sel="${1:-}"
cwd="${2:-$PWD}"
dir="$(handoff_dir "$cwd")"
f=""
if [ -z "$sel" ]; then
  f="$(newest_session_file "$dir")"
elif printf '%s' "$sel" | grep -Eq '^[0-9]+$'; then
  f="$(session_files "$dir" | sed -n "${sel}p")"
else
  f="$(session_files "$dir" | grep -F -- "$sel" | head -1)"
fi
if [ -z "$f" ] || [ ! -f "$f" ]; then
  echo "no handoff matches '$sel' in $dir" >&2
  exit 1
fi

if [ "$adopt" = 1 ]; then
  me="$(current_session_id)"
  root="$(root_of_file "$f")"
  if [ -z "$me" ]; then
    echo "cannot join: CLAUDE_CODE_SESSION_ID is not set in this shell" >&2
  elif [ -z "$root" ]; then
    echo "cannot join: the file has no session id in its header" >&2
  elif [ "$(thread_root "$dir" "$me")" = "$root" ]; then
    echo "already in this thread ($me)" >&2
  else
    st="$(state_dir "$dir")"; mkdir -p "$st"
    # Leave any previous thread, drop a file of our own, join the chosen one.
    mine="$(session_file_for "$dir" "$me")"
    [ -n "$mine" ] && [ "$mine" != "$f" ] && [ "$(root_of_file "$mine")" = "$me" ] && rm -f "$mine"
    cp -f "$f" "$(frozen_file "$dir" "$root")"
    printf '%s' "$root" > "$st/${me:0:8}.adopt"
    printf '%s\n' "$me" >> "$st/${root:0:8}.members"
    set_header_line "$f" "Status" "🟢 in work (joined by session ${me:0:8} at $(date '+%Y-%m-%d %H:%M'))"
    # Render the thread now if this session's transcript is already known (after its first Stop).
    t="$(transcript_of "$dir" "$me")"
    if [ -n "$t" ]; then
      jq -nc --arg t "$t" --arg s "$me" --arg c "$cwd" '{session_id:$s, transcript_path:$t, cwd:$c}' | "$HERE/save-handoff.sh"
      f="$(session_file_for "$dir" "$me")"
    fi
    echo "joined thread ${root:0:8}: this session now writes into $(basename "$f")" >&2
  fi
fi

printf 'Handoff file: %s\n\n' "$f"
cat "$f"
