#!/usr/bin/env bash
# SessionEnd hook. Removes this session's open mark and sets the thread file's status:
# still 🟢 if another session of the thread is open, ⚪ saved otherwise.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
command -v jq >/dev/null 2>&1 || exit 0
is_headless && exit 0
input="$(cat)"
printf '%s' "$input" | jq -e . >/dev/null 2>&1 || exit 0
sid="$(printf '%s' "$input" | jq -r '.session_id // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[ -n "$sid" ] || exit 0
[ -n "$cwd" ] || cwd="$PWD"
dir="$(handoff_dir "$cwd")"
rm -f "$(open_mark "$dir" "$sid")"
f="$(session_file_for "$dir" "$sid")"
[ -n "$f" ] && [ -f "$f" ] || exit 0
root="$(thread_root "$dir" "$sid")"
others="$(open_members "$dir" "$root" | tr '\n' ' ' | sed 's/ $//')"
if [ -n "$others" ]; then
  set_header_line "$f" "Status" "🟢 in work (open: $others)"
else
  set_header_line "$f" "Status" "⚪ saved (session closed $(date '+%Y-%m-%d %H:%M'))"
fi
latest="$dir/LATEST.md"
[ -f "$latest" ] && [ "$(root_of_file "$latest")" = "$root" ] && cp -f "$f" "$latest"
exit 0
