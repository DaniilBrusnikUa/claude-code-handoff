#!/usr/bin/env bash
# Prints one handoff file: by number from the list this session was shown (handoff-list.sh
# or the start index), by session id, or by part of the file name. No argument: the newest.
#   --adopt   the current session joins that file's thread: from now on its hooks write into
#             this file (together with the earlier sessions), and it gets no file of its own.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
adopt=0
[ "${1:-}" = "--adopt" ] && { adopt=1; shift; }
sel="${1:-}"
cwd="$(skill_project_dir "${2:-}")"
dir="$(handoff_dir "$cwd")"
me="$(current_session_id)"
match_name() {  # files on stdin whose base name contains $1
  local p
  while IFS= read -r p; do
    case "$(basename "$p")" in *"$1"*) printf '%s\n' "$p" ;; esac
  done
}
f=""
if [ -z "$sel" ]; then
  f="$(newest_session_file "$dir")"
elif printf '%s' "$sel" | grep -Eq '^[0-9]+$'; then
  # Numbers come from the list printed to this session (saved at print time, so a file written
  # in between cannot shift them); without such a list, from the current order.
  idx=""; [ -n "$me" ] && idx="$(state_dir "$dir")/${me:0:8}.index"
  if [ -n "$idx" ] && [ -s "$idx" ]; then
    f="$(sed -n "${sel}p" "$idx")"
    [ -n "$f" ] && [ ! -f "$f" ] && { echo "entry $sel of the list ($(basename "$f")) no longer exists; run the list again" >&2; exit 1; }
  else
    f="$(session_files "$dir" | sed -n "${sel}p")"
  fi
else
  f="$(session_files "$dir" | match_name "$sel" | head -1)"
fi
if [ -z "$f" ] || [ ! -f "$f" ]; then
  echo "no handoff matches '$sel' in $dir" >&2
  exit 1
fi

if [ "$adopt" = 1 ]; then
  root="$(root_of_file "$f")"
  if [ -z "$me" ]; then
    echo "cannot join: CLAUDE_CODE_SESSION_ID is not set in this shell" >&2
  elif [ -z "$root" ]; then
    echo "cannot join: the file has no valid session id in its header" >&2
  elif [ "$(thread_root "$dir" "$me")" = "$root" ]; then
    echo "already in this thread ($me)" >&2
  else
    st="$(state_dir "$dir")"; mkdir -p "$st"
    # A file of our own: dropped when it only holds this session, kept when other sessions
    # joined it (their history lives there); those sessions follow us into the new thread.
    mine="$(session_file_for "$dir" "$me")"
    if [ -n "$mine" ] && [ "$mine" != "$f" ] && [ "$(root_of_file "$mine")" = "$me" ]; then
      if [ -s "$st/${me:0:8}.members" ]; then
        echo "Note: kept $(basename "$mine"): other sessions wrote into it; they join the new thread too" >&2
        audit "$dir" "$me" "adopt-keep" "$mine"
        while IFS= read -r m; do
          [ -n "$m" ] && valid_sid "$m" && [ "$m" != "$root" ] || continue
          printf '%s' "$root" > "$st/${m:0:8}.adopt"
          printf '%s\n' "$m" >> "$st/${root:0:8}.members"
        done < "$st/${me:0:8}.members"
      elif is_handoff_file "$mine"; then
        audit "$dir" "$me" "adopt-rm" "$mine"
        rm -f "$mine"
      fi
    fi
    cp -f "$f" "$(frozen_file "$dir" "$root")"
    printf '%s' "$root" > "$st/${me:0:8}.adopt"
    printf '%s\n' "$me" >> "$st/${root:0:8}.members"
    audit "$dir" "$me" "adopt" "$f"
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
