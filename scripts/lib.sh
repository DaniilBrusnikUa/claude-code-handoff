#!/usr/bin/env bash
# Shared helpers. Sourced by the other scripts.
#
# Settings (environment variables, e.g. in the "env" block of
# ~/.claude/settings.json or a project's .claude/settings.local.json):
#
#   CLAUDE_HANDOFF_ROOT              cwd (default) -> "the project" is the directory the session started in
#                                    git           -> "the project" is the git repository root, so sessions
#                                                     started in subfolders of one repo share one handoff folder
#   CLAUDE_HANDOFF_IN_PROJECT        true (default) -> <project>/.claude/handoffs/
#                                    false          -> ~/.claude/handoffs/<project-slug>/
#   CLAUDE_HANDOFF_DIR               explicit directory; overrides the setting above.
#                                    Absolute, ~/..., or relative to the project. Use a directory of its
#                                    own: retention is skipped while other markdown files live there.
#   CLAUDE_HANDOFF_AUTOLOAD          compact (default) | full | false
#   CLAUDE_HANDOFF_LOAD_CHARS        max characters injected in "full" mode (16000)
#   CLAUDE_HANDOFF_COMPACT_CHARS     max characters per block in "compact" mode (3000)
#   CLAUDE_HANDOFF_INDEX             how many recent sessions to list at start (5)
#   CLAUDE_HANDOFF_KEEP              thread FILES kept per project (50; counts files, not days;
#                                    values 1-4 are raised to 5; 0 disables retention)
#   CLAUDE_HANDOFF_MAX_PROMPTS       how many user requests to keep (25)
#   CLAUDE_HANDOFF_PROMPT_CHARS      max characters per user request (400)
#   CLAUDE_HANDOFF_MAX_REPLIES       end-of-turn replies to keep (5)
#   CLAUDE_HANDOFF_REPLY_CHARS       max characters of the newest reply (4000)
#   CLAUDE_HANDOFF_SHORT_REPLY_CHARS max characters of each older reply (800)
#   CLAUDE_HANDOFF_AUTO_NOTES        0 (off) | N -> every N user turns Claude updates the notes block (costs one model turn)
#   CLAUDE_HANDOFF_COMPACT_SUMMARY_CHARS  max characters of the compaction summary kept in the file (6000)
#
# Non-integer values of the numeric settings fall back to the default.

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

is_false() {
  case "$(lower "$1")" in false|0|no|off) return 0 ;; *) return 1 ;; esac
}

# int_setting <value> <default> -> the value if it is a non-negative integer, else the default
int_setting() {
  case "$1" in ''|*[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac
}

# plugin_version -> "version" from .claude-plugin/plugin.json next to the scripts
plugin_version() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$here/../.claude-plugin/plugin.json" 2>/dev/null | head -1
}

# project_slug <path> -> one flat name per project; "/" and spaces are percent-encoded so
# /a/b-c and /a/b/c do not collide
project_slug() {
  printf '%s' "$1" | sed -e 's#^/##' -e 's#%#%25#g' -e 's#/#%2F#g' -e 's# #%20#g'
}

# project_root <session cwd> -> the directory that counts as "the project"
project_root() {
  local cwd="$1" top=""
  if [ "$(lower "${CLAUDE_HANDOFF_ROOT:-cwd}")" = "git" ]; then
    top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
  fi
  printf '%s' "${top:-$cwd}"
}

# handoff_dir <session cwd> -> prints the directory that holds the handoff files
handoff_dir() {
  local cwd
  cwd="$(project_root "$1")"
  if [ -n "${CLAUDE_HANDOFF_DIR:-}" ]; then
    case "$CLAUDE_HANDOFF_DIR" in
      /*)  printf '%s' "$CLAUDE_HANDOFF_DIR" ;;
      "~"*) printf '%s%s' "$HOME" "${CLAUDE_HANDOFF_DIR#\~}" ;;
      *)   printf '%s/%s' "$cwd" "$CLAUDE_HANDOFF_DIR" ;;
    esac
    return
  fi
  if is_false "${CLAUDE_HANDOFF_IN_PROJECT:-true}"; then
    printf '%s/.claude/handoffs/%s' "$HOME" "$(project_slug "$cwd")"
  else
    printf '%s/.claude/handoffs' "$cwd"
  fi
}

# ---- the project seen from a skill -------------------------------------------------
# Hooks get the session's cwd from Claude Code. Scripts run from a skill only have $PWD,
# which follows every `cd` the model made in the Bash tool. The Stop hook therefore records
# the session's cwd in .state/<sid8>.cwd, and skills resolve the project in this order:
#   1. an explicit argument, 2. $CLAUDE_PROJECT_DIR, 3. the .cwd sidecar of this session found
#   by walking up from $PWD (or in the handoff dir of $PWD), 4. $PWD.
skill_project_dir() {
  local sid d p
  [ -n "${1:-}" ] && { printf '%s' "$1"; return; }
  [ -n "${CLAUDE_PROJECT_DIR:-}" ] && { printf '%s' "$CLAUDE_PROJECT_DIR"; return; }
  sid="$(current_session_id)"
  if [ -n "$sid" ]; then
    d="$PWD"
    while :; do
      p="$d/.claude/handoffs/.state/${sid:0:8}.cwd"
      [ -s "$p" ] && { cat "$p"; return; }
      [ "$d" = "/" ] && break
      d="$(dirname "$d")"
    done
    p="$(state_dir "$(handoff_dir "$PWD")")/${sid:0:8}.cwd"
    [ -s "$p" ] && { cat "$p"; return; }
  fi
  printf '%s' "$PWD"
}

# ---- handoff files -----------------------------------------------------------------
# is_handoff_file <f> -> 0 when the name is <date>_<time>[_<title>]_<id8>.md and the file
# carries the epoch marker. Only such files are ever deleted, renamed or listed.
is_handoff_file() {
  [ -f "$1" ] || return 1
  printf '%s' "$(basename "$1")" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}(_.*)?_[0-9a-f]{8}\.md$' || return 1
  grep -q '^<!-- handoff:updated_epoch:' "$1" 2>/dev/null
}

# file_mtime <file> -> modification time as epoch seconds (BSD and GNU date both take -r)
file_mtime() { date -r "$1" +%s 2>/dev/null || printf '0'; }

# session_files <dir> -> handoff files, newest first by the updated_epoch each file carries
# (a copied or synced directory keeps that order; mtime is only the fallback). File names
# come from title_slug, which strips whitespace and control characters, so one line is one
# file; everything else (LATEST.md, the user's own markdown) is filtered out.
session_files() {
  local f ep
  for f in "$1"/*.md; do
    is_handoff_file "$f" || continue
    ep="$(epoch_of "$f")"
    case "$ep" in ''|*[!0-9]*|0) ep="$(file_mtime "$f")" ;; esac
    printf '%s\t%s\n' "$ep" "$f"
  done 2>/dev/null | sort -t "$(printf '\t')" -k1,1nr -k2,2 | cut -f2-
}

# foreign_md_files <dir> -> markdown files in the directory that are not handoff files
foreign_md_files() {
  local f
  ls "$1"/*.md 2>/dev/null | while IFS= read -r f; do
    [ "$(basename "$f")" = "LATEST.md" ] && continue
    is_handoff_file "$f" || printf '%s\n' "$f"
  done
}

newest_session_file() { session_files "$1" | head -1; }

# compact_sidecar <dir> <session id> -> file that stores compaction summaries
compact_sidecar() { printf '%s/.state/%s.compact.md' "$1" "${2:0:8}"; }

# section <file> <heading> -> body of "## <heading>" up to the next "## "
section() {
  awk -v h="## $2" '
    index($0, h) == 1 && length($0) == length(h) { f = 1; next }
    /^## / { if (f) exit }
    f { print }' "$1"
}

# header_field <file> <name> -> value of "- <name>: `value`" or "- <name>: value"
header_field() {
  sed -n "s/^- $2: \`\\{0,1\\}\\([^\`]*\\)\`\\{0,1\\}$/\\1/p" "$1" | head -1
}

# epoch_of <file> -> the updated_epoch comment written by save-handoff.sh
epoch_of() { sed -n 's/^<!-- handoff:updated_epoch:\([0-9]*\) -->$/\1/p' "$1" | head -1; }

# ---- notes -------------------------------------------------------------------------
# The block between the two marker lines is the only part of the file the model writes.
# Its source of truth is .state/<root8>.notes.md (no markers inside); the .md file shows a
# copy on every render. Markers count only as whole lines, and the block ends at the first
# end marker: a marker quoted inside a reply can therefore not re-open it.
NOTES_START='<!-- handoff:notes:start -->'
NOTES_END='<!-- handoff:notes:end -->'
NOTES_PLACEHOLDER='_No notes yet. Run /handoff:notes in the session to record decisions, open questions and next steps here._'

notes_sidecar() { printf '%s/.state/%s.notes.md' "$1" "${2:0:8}"; }

# notes_block_of <file> -> the lines between the markers (markers excluded), repaired:
# a block that swallowed the rest of the file (older versions) is cut at the first line that
# is a second start marker or a section heading of the file body.
notes_block_of() {
  awk -v s="$NOTES_START" -v e="$NOTES_END" '
    !f && $0 == s { f = 1; next }
    f && $0 == e { exit }
    f && ($0 == s || index($0, "## ") == 1 || index($0, "_Generated by the handoff plugin") == 1) { exit }
    f { print }' "$1" 2>/dev/null
}

# notes_of <file> -> the notes, empty if still the placeholder
notes_of() { notes_block_of "$1" | grep -v '^_No notes yet'; }

# sidecar_notes <notes file> -> its text without marker or placeholder lines and without
# leading blank lines (the model may paste the markers in; they are not part of the notes)
sidecar_notes() {
  grep -v -e "^$NOTES_START\$" -e "^$NOTES_END\$" -e '^_No notes yet' "$1" 2>/dev/null | sed -e '/./,$!d'
}

# MARK_NEUTRAL: what a marker quoted in a reply, a summary or the notes becomes on the way
# into the file ("<!-- handoff:" with the colon replaced by U+2011). scrub.jq carries the same
# literal; tests check the two stay byte-identical.
MARK_NEUTRAL='<!-- handoff‑'
neutralise_markers() { sed "s/<!-- handoff:/$MARK_NEUTRAL/g"; }

# ---- text read back from files ------------------------------------------------------
# Everything printed to the terminal or injected into a session passes through here: control
# characters out (a title is model text; a cloned repository may carry anything).
clean_text() { tr -d '\000-\010\013-\037\177'; }

# plain_md -> one line of notes without its markdown dressing: bold, code, list bullet,
# heading marks, the "Next action:" label itself
plain_md() {
  sed -e 's/\*\*//g' -e 's/`//g' -e 's/^[[:space:]]*[-*] //' -e 's/^#* *//' -e 's/^[0-9]*\. //' -e 's/^[Nn]ext action *: *//' -e 's/^[[:space:]]*//'
}

# utf8_locale -> a UTF-8 locale that exists on this machine, so ${#s} and ${s:0:n} count
# characters (hooks often run with LANG unset); "" when none is available
utf8_locale() {
  local l
  for l in C.UTF-8 en_US.UTF-8 UTF-8; do
    if [ "$(LC_ALL=$l bash -c 's=é; printf %s "${#s}"' 2>/dev/null)" = 1 ]; then printf '%s' "$l"; return; fi
  done
}

# file_title <file> -> the title line, cleaned, or "untitled" (the writer stores "untitled session")
file_title() {
  local t
  t="$(sed -n '1s/^# Handoff: //p' "$1" | clean_text)"
  case "$t" in ''|'untitled session') printf 'untitled' ;; *) printf '%s' "$t" ;; esac
}

# next_of_notes <dir> <root id> -> the one line that says what comes next: the "Next action"
# line of the thread's notes, else the first non-empty notes line; markdown stripped, ≤ 60 chars
# [file] is read when the thread has no sidecar yet (files written by older versions).
next_of_notes() {
  local nf="$(notes_sidecar "$1" "$2")" l="" text=""
  if [ -s "$nf" ]; then text="$(sidecar_notes "$nf")"
  elif [ -n "${3:-}" ] && [ -f "$3" ]; then text="$(notes_of "$3")"; fi
  [ -n "$text" ] || return 0
  # Preference: the "Next action" line, then the first item under "Next steps", then the first line.
  l="$(printf '%s\n' "$text" | grep -i -m1 'next action' | plain_md)"
  [ -n "$l" ] || l="$(printf '%s\n' "$text" | awk 'f && NF { print; exit } { if (match(tolower($0), /next steps?[^:]*:[[:space:]]*/)) { rest = substr($0, RSTART + RLENGTH); if (rest ~ /[^[:space:]*]/) { print rest; exit } f = 1 } }' | plain_md)"
  [ -n "$l" ] || l="$(printf '%s\n' "$text" | grep -v '^[[:space:]]*$' | head -1 | plain_md)"
  # Drop the label itself ("Next action:", "1.", "- ") so only the step remains.
  l="$(printf '%s' "$l" | awk '{ s = $0; if (match(tolower(s), /^[[:space:]]*(next action|next steps?)[[:space:]]*:?[[:space:]]*/)) s = substr(s, RLENGTH + 1); sub(/^[[:space:]]*([0-9]+[.)]|[-*])[[:space:]]*/, "", s); print s }')"
  # The line goes into the file header and the terminal: scrubbed like every other copy of user text.
  printf '%s' "$l" | clean_text | jq -Rr -L "$(dirname "${BASH_SOURCE[0]}")" 'include "scrub"; scrub' 2>/dev/null | cut -c1-60
}

# cache_ttl <transcript> -> 300 when the last request was cached on the 5-minute tier only,
# else 3600 (the 1-hour tier that subscriptions get within their included usage)
cache_ttl() {
  local u
  u="$(tail -n 200 "$1" 2>/dev/null | jq -r 'select(.type == "assistant" and .message.usage != null) | .message.usage.cache_creation // {} | "\(.ephemeral_5m_input_tokens // 0) \(.ephemeral_1h_input_tokens // 0)"' 2>/dev/null | tail -1)"
  case "$u" in
    "0 0"|"") printf '3600' ;;
    *" 0") printf '300' ;;
    *) printf '3600' ;;
  esac
}

# tracked_in_git <dir> <cwd> -> 0 when the handoff directory holds files tracked by the
# project's repository (someone committed it): the plugin then writes nothing there
tracked_in_git() {
  [ -d "$1" ] || return 1
  git -C "$2" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  [ -n "$(git -C "$2" ls-files -- "$1" 2>/dev/null | head -1)" ]
}

# ---- age / status ------------------------------------------------------------------
# age_text <seconds> -> "12 min" / "3 h" / "2 d"
age_text() {
  local s="$1"
  if [ "$s" -lt 3600 ]; then printf '%d min' $((s / 60))
  elif [ "$s" -lt 172800 ]; then printf '%d h' $((s / 3600))
  else printf '%d d' $((s / 86400)); fi
}

# current_session_id -> the id of the Claude Code session this shell belongs to (set by Claude Code)
current_session_id() { printf '%s' "${CLAUDE_CODE_SESSION_ID:-}"; }

# status_icon <file> -> the icon of the Status header line (🟢 in work, ⚪ saved), or "" if none
status_icon() { header_field "$1" Status | awk '{print $1}'; }

# set_header_line <file> <name> <value> -> replace "- <name>: ..." or insert it before the epoch comment
set_header_line() {
  local f="$1" name="$2" value="$3" tmp="$1.tmp.$$"
  awk -v n="- $name:" -v line="- $name: $value" '
    index($0, n) == 1 { print line; done = 1; next }
    /^<!-- handoff:updated_epoch:/ && !done { print line; done = 1 }
    { print }' "$f" > "$tmp" && mv -f "$tmp" "$f"
}

# ---- ids ---------------------------------------------------------------------------
# valid_sid <id> -> 0 for a full session id (uuid). Ids read from files and sidecars are
# checked before they become part of a path.
valid_sid() {
  printf '%s' "$1" | grep -Eq '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
}

# ---- threads: several sessions writing one file ------------------------------------
# A session that runs /handoff:load joins the chosen file's thread: its transcript is
# rendered into that file together with the earlier sessions', and it gets no file of its own.
#   .state/<sid8>.adopt       full id of the thread root this session joined
#   .state/<root8>.members    full ids of the sessions that joined, in order
#   .state/<sid8>.transcript  transcript path of that session (written by the Stop hook)
#   .state/<sid8>.cwd         the session's project directory (written by the Stop hook)
#   .state/<sid8>.index       the numbered list this session was last shown (for /handoff:load <n>)
#   .state/<root8>.notes.md   the notes block of the thread (source of truth)
#   .state/<root8>.lock/      held while the thread's file is rendered
#   .state/audit.log          one line per delete / rename / adopt of a handoff file

state_dir() { printf '%s/.state' "$1"; }

# thread_root <dir> <session id> -> full id of the root of the thread this session belongs to
thread_root() {
  local dir="$1" sid="$2" next="" i=0
  while [ $i -lt 10 ]; do
    next="$(cat "$(state_dir "$dir")/${sid:0:8}.adopt" 2>/dev/null || true)"
    [ -n "$next" ] && [ "$next" != "$sid" ] && valid_sid "$next" || break
    sid="$next"; i=$((i + 1))
  done
  printf '%s' "$sid"
}

# thread_members <dir> <root id> -> full ids: root first, then the sessions that joined, in order
thread_members() {
  local dir="$1" root="$2" m
  printf '%s\n' "$root"
  [ -f "$(state_dir "$dir")/${root:0:8}.members" ] || return 0
  grep -v "^$root\$" "$(state_dir "$dir")/${root:0:8}.members" | awk 'NF && !seen[$0]++' | while IFS= read -r m; do
    valid_sid "$m" && printf '%s\n' "$m"
  done
}

# transcript_of <dir> <session id> [fallback dir] -> transcript path recorded for that session
transcript_of() {
  local p
  p="$(cat "$(state_dir "$1")/${2:0:8}.transcript" 2>/dev/null || true)"
  [ -n "$p" ] && [ -f "$p" ] && { printf '%s' "$p"; return; }
  [ -n "${3:-}" ] && [ -f "$3/$2.jsonl" ] && printf '%s' "$3/$2.jsonl"
}

# root_of_file <file> -> full id of the thread root (hidden comment; older files: the Session
# line); empty when the file carries no valid id
root_of_file() {
  local r
  r="$(sed -n 's/^<!-- handoff:root:\([^ ]*\) -->$/\1/p' "$1" | head -1)"
  [ -n "$r" ] || r="$(header_field "$1" Session)"
  valid_sid "$r" && printf '%s' "$r"
}

# root8_of_file <file> -> short root id: from the header, else from the file name
root8_of_file() {
  local r
  r="$(root_of_file "$1")"
  if [ -n "$r" ]; then printf '%s' "${r:0:8}"
  else printf '%s' "$(basename "$1" .md)" | sed -n 's/.*_\([0-9a-f]\{8\}\)$/\1/p'; fi
}

# session_file_for <dir> <session id> -> the file of that session's thread, if any
session_file_for() {
  local root f
  root="$(thread_root "$1" "$2")"
  for f in "$1"/*_"${root:0:8}".md; do
    is_handoff_file "$f" && { printf '%s' "$f"; return; }
  done
  return 0
}

# ---- audit -------------------------------------------------------------------------
# audit <dir> <session id> <action> <path> -> appends one line to .state/audit.log
audit() {
  local log
  log="$(state_dir "$1")/audit.log"
  mkdir -p "$(dirname "$log")" 2>/dev/null || return 0
  printf '%s %s %s %s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "${2:0:8}" "$(plugin_version)" "$3" "$4" >> "$log"
  if [ "$(wc -l < "$log" | tr -d ' ')" -gt 2000 ]; then
    tail -n 1500 "$log" > "$log.tmp.$$" && mv -f "$log.tmp.$$" "$log"
  fi
}

# ---- lock --------------------------------------------------------------------------
# take_lock <dir> <root id> -> 0 when the thread's render lock is held (waits up to 10 s;
# a lock older than 30 s is considered left behind by a killed hook and taken over)
take_lock() {
  local l now t i=0
  l="$(state_dir "$1")/${2:0:8}.lock"
  while ! mkdir "$l" 2>/dev/null; do
    now="$(date +%s)"; t="$(cat "$l/t" 2>/dev/null || echo 0)"
    case "$t" in ''|*[!0-9]*) t=0 ;; esac
    if [ $((now - t)) -gt 30 ]; then rm -rf "$l"; continue; fi
    i=$((i + 1)); [ $i -ge 20 ] && return 1
    sleep 0.5
  done
  date +%s > "$l/t"
  return 0
}
release_lock() { rm -rf "$(state_dir "$1")/${2:0:8}.lock"; }

# ---- headless runs ----------------------------------------------------------------
# `claude -p …` and SDK sessions are new sessions each time; the plugin stays silent
# there (no files, no context injected). CLAUDE_HANDOFF_HEADLESS=true forces it on.
is_headless() {
  [ "$(lower "${CLAUDE_HANDOFF_HEADLESS:-}")" = "true" ] && return 1
  case "$(lower "${CLAUDE_CODE_SESSION_ATTENDED:-}")" in 0|false|no) return 0 ;; esac
  case "$(lower "${CLAUDE_CODE_ENTRYPOINT:-}")" in sdk*|headless*) return 0 ;; esac
  return 1
}

# transcript_is_headless <transcript> -> 0 when the transcript's own entrypoint (first entry
# that carries one, within the first 20 lines) says sdk/headless
transcript_is_headless() {
  case "$(head -n 20 "$1" 2>/dev/null | jq -r 'select(.entrypoint != null) | .entrypoint' 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')" in
    sdk*|headless*) return 0 ;; *) return 1 ;; esac
}

# ---- open sessions ----------------------------------------------------------------
# Every Stop touches .state/<sid8>.open; SessionEnd removes it and writes .state/<sid8>.closed
# (epoch). A Stop that started before the SessionEnd (hooks run async) sees the newer .closed
# and does not re-open. A thread is "in work" while any of its sessions has the mark.
open_mark() { printf '%s/.state/%s.open' "$1" "${2:0:8}"; }
closed_mark() { printf '%s/.state/%s.closed' "$1" "${2:0:8}"; }

# session_is_open <dir> <session id> -> 0 when the session has an open mark that is not stale.
# A crash leaves the mark behind (SessionEnd never ran): it counts only while the mark or the
# session's transcript was touched in the last 6 hours.
OPEN_STALE_SECONDS=21600
session_is_open() {
  local mk t now
  mk="$(open_mark "$1" "$2")"
  [ -f "$mk" ] || return 1
  now="$(date +%s)"
  [ $((now - $(file_mtime "$mk"))) -lt "$OPEN_STALE_SECONDS" ] && return 0
  t="$(transcript_of "$1" "$2")"
  [ -n "$t" ] && [ $((now - $(file_mtime "$t"))) -lt "$OPEN_STALE_SECONDS" ] && return 0
  return 1
}

# open_members <dir> <root id> -> short ids of the thread's sessions that are open
open_members() {
  local m
  while IFS= read -r m; do
    [ -n "$m" ] && session_is_open "$1" "$m" && printf '%s\n' "${m:0:8}"
  done <<< "$(thread_members "$1" "$2")"
}

# frozen_file <dir> <root id> -> snapshot of the rendered thread file, used when a
# member's transcript was deleted (Claude Code keeps transcripts cleanupPeriodDays, 30 by default)
frozen_file() { printf '%s/.state/%s.frozen.md' "$1" "${2:0:8}"; }

# ensure_git_excluded <dir> -> add the handoff directory to .git/info/exclude of its repository
# (local to this clone, never committed) when it is inside a git work tree and not ignored yet.
# Physical paths on both sides, so a symlinked cwd still yields a relative line.
ensure_git_excluded() {
  local dir top rel excl
  dir="$(cd "$1" 2>/dev/null && pwd -P)" || return 0
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$top" ] || return 0
  top="$(cd "$top" 2>/dev/null && pwd -P)" || return 0
  git -C "$top" check-ignore -q "$dir" 2>/dev/null && return 0
  excl="$(git -C "$top" rev-parse --git-path info/exclude 2>/dev/null)"
  [ -n "$excl" ] || return 0
  case "$excl" in /*) ;; *) excl="$top/$excl" ;; esac
  rel="${dir#"$top"/}"
  case "$rel" in /*) return 0 ;; esac
  mkdir -p "$(dirname "$excl")" 2>/dev/null
  grep -qxF "/$rel/" "$excl" 2>/dev/null || printf '/%s/\n' "$rel" >> "$excl"
}
