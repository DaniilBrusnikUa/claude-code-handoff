#!/usr/bin/env bash
# Prints the handoff files of a project as a numbered list, newest first.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
cwd="${1:-$PWD}"
dir="$(handoff_dir "$cwd")"
now="$(date +%s)"
i=0
session_files "$dir" | while IFS= read -r f; do
  i=$((i + 1))
  title="$(sed -n '1s/^# Handoff: //p' "$f")"
  br="$(header_field "$f" Branch)"
  fsid="$(header_field "$f" Session)"
  ep="$(epoch_of "$f")"; age="updated ?"
  [ -n "$ep" ] && [ "$ep" -gt 0 ] && age="$(age_text $((now - ep))) ago"
  st="$(header_field "$f" Started)"
  ic="$(status_icon "$f")"
  n1="$(notes_of "$f" | head -1 | cut -c1-100)"
  printf '%d. %s %s | %s | %s%s | id %s | %s%s\n' "$i" "${ic:-⚪}" "${st:-?}" "$title" "$age" "${br:+ | $br}" "${fsid:0:8}" "$(basename "$f")" "${n1:+ | notes: $n1}"
done
