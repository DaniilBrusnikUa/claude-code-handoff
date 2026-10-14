#!/usr/bin/env bash
# Prints the handoff files of a project as a numbered list, newest first, and remembers the
# order for this session (.state/<sid8>.index) so that handoff-show.sh <number> picks the
# same file even if another session writes in between.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
cwd="$(skill_project_dir "${1:-}")"
dir="$(handoff_dir "$cwd")"
now="$(date +%s)"
sid="$(current_session_id)"
idx=""
if [ -n "$sid" ] && mkdir -p "$(state_dir "$dir")" 2>/dev/null; then
  idx="$(state_dir "$dir")/${sid:0:8}.index"; : > "$idx"
fi
i=0
session_files "$dir" | while IFS= read -r f; do
  i=$((i + 1))
  [ -n "$idx" ] && printf '%s\n' "$f" >> "$idx"
  title="$(sed -n '1s/^# Handoff: //p' "$f")"
  br="$(header_field "$f" Branch)"
  r8="$(root8_of_file "$f")"
  ep="$(epoch_of "$f")"; age="updated ?"
  [ -n "$ep" ] && [ "$ep" -gt 0 ] && age="$(age_text $((now - ep))) ago"
  st="$(header_field "$f" Started)"
  ic="$(status_icon "$f")"
  n1="$(notes_of "$f" | head -1 | cut -c1-100)"
  printf '%d. %s %s | %s | %s%s | id %s | %s%s\n' "$i" "${ic:-⚪}" "${st:-?}" "$title" "$age" "${br:+ | $br}" "$r8" "$(basename "$f")" "${n1:+ | notes: $n1}"
done
