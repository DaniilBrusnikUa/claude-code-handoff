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
#                                    Absolute, ~/..., or relative to the project.
#   CLAUDE_HANDOFF_AUTOLOAD          compact (default) | full | false
#   CLAUDE_HANDOFF_LOAD_CHARS        max characters injected in "full" mode (16000)
#   CLAUDE_HANDOFF_COMPACT_CHARS     max characters per block in "compact" mode (3000)
#   CLAUDE_HANDOFF_INDEX             how many recent sessions to list at start (5)
#   CLAUDE_HANDOFF_KEEP              session files to keep per project (50)
#   CLAUDE_HANDOFF_MAX_PROMPTS       how many user requests to keep (25)
#   CLAUDE_HANDOFF_PROMPT_CHARS      max characters per user request (400)
#   CLAUDE_HANDOFF_MAX_REPLIES       end-of-turn replies to keep (5)
#   CLAUDE_HANDOFF_REPLY_CHARS       max characters of the newest reply (4000)
#   CLAUDE_HANDOFF_SHORT_REPLY_CHARS max characters of each older reply (800)
#   CLAUDE_HANDOFF_AUTO_NOTES        0 (off) | N -> every N user turns Claude updates the notes block (costs one model turn)
#   CLAUDE_HANDOFF_COMPACT_SUMMARY_CHARS  max characters of the compaction summary kept in the file (6000)

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

is_false() {
  case "$(lower "$1")" in false|0|no|off) return 0 ;; *) return 1 ;; esac
}

project_slug() {
  printf '%s' "$1" | sed -e 's#^/##' -e 's#[/ ]#-#g'
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

# session_files <dir> -> session files, newest first, excluding LATEST.md
session_files() {
  ls -t "$1"/*.md 2>/dev/null | grep -v '/LATEST\.md$'
}

newest_session_file() { session_files "$1" | head -1; }

# session_file_for <dir> <session id> -> the file of that session, if any
session_file_for() {
  ls "$1"/*_"${2:0:8}".md 2>/dev/null | head -1
}

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

# notes_of <file> -> the /handoff notes, empty if still the placeholder
notes_of() {
  awk '/<!-- handoff:notes:start -->/{f=1; next} /<!-- handoff:notes:end -->/{f=0} f' "$1" | grep -v '^_No notes yet'
}

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

# ---- threads: several sessions writing one file ------------------------------------
# A session that runs /handoff:load joins the chosen file's thread: its transcript is
# rendered into that file together with the earlier sessions', and it gets no file of its own.
#   .state/<sid8>.adopt       full id of the thread root this session joined
#   .state/<root8>.members    full ids of the sessions that joined, in order
#   .state/<sid8>.transcript  transcript path of that session (written by the Stop hook)

state_dir() { printf '%s/.state' "$1"; }

# thread_root <dir> <session id> -> full id of the root of the thread this session belongs to
thread_root() {
  local dir="$1" sid="$2" next="" i=0
  while [ $i -lt 10 ]; do
    next="$(cat "$(state_dir "$dir")/${sid:0:8}.adopt" 2>/dev/null || true)"
    [ -n "$next" ] && [ "$next" != "$sid" ] || break
    sid="$next"; i=$((i + 1))
  done
  printf '%s' "$sid"
}

# thread_members <dir> <root id> -> full ids: root first, then the sessions that joined, in order
thread_members() {
  local dir="$1" root="$2"
  printf '%s\n' "$root"
  [ -f "$(state_dir "$dir")/${root:0:8}.members" ] && grep -v "^$root\$" "$(state_dir "$dir")/${root:0:8}.members" | awk 'NF && !seen[$0]++'
}

# transcript_of <dir> <session id> [fallback dir] -> transcript path recorded for that session
transcript_of() {
  local p
  p="$(cat "$(state_dir "$1")/${2:0:8}.transcript" 2>/dev/null || true)"
  [ -n "$p" ] && [ -f "$p" ] && { printf '%s' "$p"; return; }
  [ -n "${3:-}" ] && [ -f "$3/$2.jsonl" ] && printf '%s' "$3/$2.jsonl"
}

# root_of_file <file> -> full id of the thread root (hidden comment; older files: the Session line)
root_of_file() {
  local r
  r="$(sed -n 's/^<!-- handoff:root:\([^ ]*\) -->$/\1/p' "$1" | head -1)"
  [ -n "$r" ] && printf '%s' "$r" || header_field "$1" Session
}

# session_file_for <dir> <session id> -> the file of that session's thread, if any
session_file_for() {
  local root
  root="$(thread_root "$1" "$2")"
  ls "$1"/*_"${root:0:8}".md 2>/dev/null | head -1
}

# ---- headless runs ----------------------------------------------------------------
# `claude -p …` and SDK sessions are new sessions each time; the plugin stays silent
# there (no files, no context injected). CLAUDE_HANDOFF_HEADLESS=true forces it on.
is_headless() {
  [ "$(lower "${CLAUDE_HANDOFF_HEADLESS:-}")" = "true" ] && return 1
  case "$(lower "${CLAUDE_CODE_SESSION_ATTENDED:-}")" in 0|false|no) return 0 ;; esac
  case "$(lower "${CLAUDE_CODE_ENTRYPOINT:-}")" in sdk*|headless*) return 0 ;; esac
  return 1
}

# transcript_is_headless <transcript> -> 0 when the transcript's own entrypoint says sdk/headless
transcript_is_headless() {
  case "$(head -n 1 "$1" 2>/dev/null | jq -r '.entrypoint // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]')" in
    sdk*|headless*) return 0 ;; *) return 1 ;; esac
}

# ---- open sessions ----------------------------------------------------------------
# Every Stop touches .state/<sid8>.open; SessionEnd removes it. A thread is "in work"
# while any of its sessions has the mark (a crash leaves a stale mark; the index shows the age).
open_mark() { printf '%s/.state/%s.open' "$1" "${2:0:8}"; }

# open_members <dir> <root id> -> short ids of the thread's sessions that have an open mark
open_members() {
  local m
  while IFS= read -r m; do
    [ -n "$m" ] && [ -f "$(open_mark "$1" "$m")" ] && printf '%s\n' "${m:0:8}"
  done <<< "$(thread_members "$1" "$2")"
}

# frozen_file <dir> <root id> -> snapshot of the rendered thread file, used when a
# member's transcript was deleted (Claude Code keeps transcripts cleanupPeriodDays, 30 by default)
frozen_file() { printf '%s/.state/%s.frozen.md' "$1" "${2:0:8}"; }

# ensure_git_excluded <dir> -> add the handoff directory to .git/info/exclude of its repository
# (local to this clone, never committed) when it is inside a git work tree and not ignored yet
ensure_git_excluded() {
  local dir="$1" top rel excl
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$top" ] || return 0
  git -C "$top" check-ignore -q "$dir" 2>/dev/null && return 0
  excl="$(git -C "$top" rev-parse --git-path info/exclude 2>/dev/null)"
  [ -n "$excl" ] || return 0
  case "$excl" in /*) ;; *) excl="$top/$excl" ;; esac
  rel="${dir#"$top"/}"
  mkdir -p "$(dirname "$excl")" 2>/dev/null
  grep -qxF "/$rel/" "$excl" 2>/dev/null || printf '/%s/\n' "$rel" >> "$excl"
}
