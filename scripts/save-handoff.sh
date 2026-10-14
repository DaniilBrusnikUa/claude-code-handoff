#!/usr/bin/env bash
# Stop hook (also called by save-compact.sh and handoff-show.sh --adopt). Reads the hook
# JSON from stdin, renders the handoff file of this session's thread from the local
# transcripts of every session in the thread. No model calls.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"
[ "${1:-}" = "--version" ] && { printf "%s\n" "$(plugin_version)"; exit 0; }
command -v jq >/dev/null 2>&1 || exit 0
is_headless && exit 0
started_at="$(date +%s)"

input="$(cat)"
printf '%s' "$input" | jq -e . >/dev/null 2>&1 || exit 0
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty')"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0
transcript_is_headless "$transcript" && exit 0
[ -n "$cwd" ] || cwd="$PWD"
[ -n "$sid" ] || sid="unknown"

dir="$(handoff_dir "$cwd")"
st="$(state_dir "$dir")"
mkdir -p "$st" 2>/dev/null || exit 0
printf '%s' "$transcript" > "$st/${sid:0:8}.transcript"
printf '%s' "$cwd" > "$st/${sid:0:8}.cwd"
# The final reply travels in a file: jq's --arg has a platform limit on argument length.
last_msg_file="$st/${sid:0:8}.last.$$"
printf '%s' "$input" | jq -r '.last_assistant_message // empty' > "$last_msg_file"
trap 'rm -f "$last_msg_file"' EXIT
# Open mark: not re-created when the session already ended while this (async) hook was running.
closed_at="$(cat "$(closed_mark "$dir" "$sid")" 2>/dev/null || true)"
case "$closed_at" in ''|*[!0-9]*) closed_at=0 ;; esac
if [ "$closed_at" -ge "$started_at" ]; then
  closed=1
else
  closed=0; touch "$(open_mark "$dir" "$sid")"; rm -f "$(closed_mark "$dir" "$sid")"
fi
ensure_git_excluded "$dir"

max_prompts="$(int_setting "${CLAUDE_HANDOFF_MAX_PROMPTS:-}" 25)"
prompt_chars="$(int_setting "${CLAUDE_HANDOFF_PROMPT_CHARS:-}" 400)"
reply_chars="$(int_setting "${CLAUDE_HANDOFF_REPLY_CHARS:-}" 4000)"
max_replies="$(int_setting "${CLAUDE_HANDOFF_MAX_REPLIES:-}" 5)"
short_reply_chars="$(int_setting "${CLAUDE_HANDOFF_SHORT_REPLY_CHARS:-}" 800)"
summary_chars="$(int_setting "${CLAUDE_HANDOFF_COMPACT_SUMMARY_CHARS:-}" 6000)"
keep="$(int_setting "${CLAUDE_HANDOFF_KEEP:-}" 50)"
[ "$keep" -gt 0 ] && [ "$keep" -lt 5 ] && keep=5

# Stop can fire while Claude Code is still appending the final assistant line to the
# transcript. Give it up to two seconds to land, so the reply and its usage are included.
for _ in 1 2 3 4; do
  [ "$(tail -n 1 "$transcript" 2>/dev/null | jq -r '.type // empty' 2>/dev/null)" = "assistant" ] && break
  sleep 0.5
done

# The thread: root session + the sessions that joined it. Transcripts are rendered in that order.
root="$(thread_root "$dir" "$sid")"
members="$(thread_members "$dir" "$root")"
transcripts=()
missing=""
tdir="$(dirname "$transcript")"
while IFS= read -r m; do
  [ -n "$m" ] || continue
  t="$(transcript_of "$dir" "$m" "$tdir")"
  [ "$m" = "$sid" ] && t="$transcript"
  if [ -n "$t" ]; then transcripts+=("$t"); else missing="${missing}${m:0:8} "; fi
done <<< "$members"
[ "${#transcripts[@]}" -gt 0 ] || transcripts=("$transcript")
thread_ids="$(printf '%s\n' "$members" | awk 'NF{printf "%s%s", (n++ ? " → " : ""), substr($0,1,8)}')"
n_members="$(printf '%s\n' "$members" | grep -c .)"
open_ids="$(open_members "$dir" "$root" | tr '\n' ' ' | sed 's/ $//')"
if [ "$closed" = 1 ] && [ -z "$open_ids" ]; then
  status_line="⚪ saved (session closed $(date '+%Y-%m-%d %H:%M'))"
else
  status_line="🟢 in work (open: ${open_ids:-${sid:0:8}})"
fi

# Git state of the project (optional).
branch=""; status=""; log=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  status="$(git -C "$cwd" status --short 2>/dev/null | head -30 | jq -Rrs -L "$HERE" 'include "scrub"; scrub' 2>/dev/null)"
  log="$(git -C "$cwd" log --oneline -5 2>/dev/null | jq -Rrs -L "$HERE" 'include "scrub"; scrub' 2>/dev/null)"
fi

# Everything we need from the transcripts, as one JSON object.
meta="$(jq -s -L "$HERE" \
  --argjson np "$max_prompts" --argjson pc "$prompt_chars" --argjson rc "$reply_chars" \
  --argjson nr "$max_replies" --argjson rcs "$short_reply_chars" --rawfile lam "$last_msg_file" --arg root "$root" '
  include "scrub";
  def ts: (.timestamp // "" | sub("\\.[0-9]+Z$"; "Z"));
  def fmt(f): if . == "" then "" else (fromdate | strflocaltime(f)) end;
  def tail(n): if length > n then .[length - n:] else . end;
  def cut(n): if length > n then .[0:n] + " [...]" else . end;
  def k(n): if n >= 1000000 then ((n / 100000 | floor) / 10 | tostring) + "M" elif n >= 1000 then ((n / 1000) | floor | tostring) + "k" else (n | tostring) end;
  # is_prompt / prompt_text come from scrub.jq: typed text (string or text blocks of an array),
  # not a tool result, not a slash command, not the post-compaction continuation message.
  def clean_title: gsub("[\u0000-\u001f\u007f]"; "");
  def tool_uses: .[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use");
  [ .[] | select(is_prompt) ] as $users
  # End-of-turn replies: the last assistant text seen before each user prompt (and before the end).
  | ( reduce .[] as $e ({ last: null, out: [] };
        if ($e | is_prompt)
        then { last: null, out: (.out + (if .last then [.last] else [] end)) }
        elif $e.type == "assistant"
        then ([ $e.message.content[]? | select(.type == "text") | .text | select(length > 0) ] | last) as $t
             | if $t then .last = $t else . end
        else . end)
      | .out + (if .last then [.last] else [] end)
      # The hook input carries the final reply directly; use it if the transcript lacks it.
      | if $lam != "" and (last // "") != $lam then . + [$lam] else . end ) as $texts
  # One API call produces several transcript rows with the same usage: count each request once.
  | ( [ .[] | select(.type == "assistant" and .message.usage != null) ]
      | unique_by(.requestId // .uuid)
      | map({ t: (ts | fmt("%H:%M")), w: (.message.usage.cache_creation_input_tokens // 0),
              r: (.message.usage.cache_read_input_tokens // 0), i: (.message.usage.input_tokens // 0),
              o: (.message.usage.output_tokens // 0) }) ) as $calls
  | {
      # The file is named after the thread root session; its title wins, later sessions only add to the file.
      title:        (([ .[] | select(.type == "ai-title" and (.sessionId // $root) == $root) | .aiTitle ] | last)
                     // ([ .[] | select(.type == "ai-title") | .aiTitle ] | last) // "" | clean_title),
      title_slug:   ((([ .[] | select(.type == "ai-title" and (.sessionId // $root) == $root) | .aiTitle ] | last)
                     // ([ .[] | select(.type == "ai-title") | .aiTitle ] | last) // "") | clean_title | gsub("[\\s/\\\\:*?\"<>|`]+"; "-") | gsub("^[-.]+|-$"; "") | .[0:60]),
      started:      ($users | first // {} | ts | fmt("%Y-%m-%d %H:%M")),
      started_slug: ($users | first // {} | ts | fmt("%Y-%m-%d_%H%M")),
      updated:      ([ .[] | ts | select(. != "") ] | max // "" | fmt("%Y-%m-%d %H:%M")),
      updated_epoch:([ .[] | ts | select(. != "") ] | max // "" | if . == "" then 0 else fromdate end),
      turns:        ($users | length),
      prompts:      ($users | tail($np) | map({ t: (ts | fmt("%m-%d %H:%M")), text: (prompt_text | gsub("</?pasted_content[^>]*>"; " ") | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "") | scrub | .[0:$pc]) })),
      replies:      ($texts | tail($nr) | to_entries
                     | map(if .key == (length - 1) then (.value | scrub | cut($rc)) else (.value | scrub | cut($rcs)) end)),
      edited:       ([ tool_uses | select(.name == "Edit" or .name == "Write" or .name == "NotebookEdit") | (.input.file_path // .input.notebook_path // empty) ] | unique),
      read:         ([ tool_uses | select(.name == "Read") | (.input.file_path // empty) ] | unique | .[0:40]),
      tokens: {
        calls: ($calls | length),
        cold:  ($calls | map(.w) | add // 0),
        warm:  ($calls | map(.r) | add // 0),
        input: ($calls | map(.i) | add // 0),
        output:($calls | map(.o) | add // 0),
        context: ($calls | last // {} | ((.w // 0) + (.r // 0) + (.i // 0))),
        big_writes: ($calls | map(select(.w >= 20000)) | tail(8) | map(.t + " " + k(.w)) | join(", "))
      }
    }' "${transcripts[@]}" 2>/dev/null)" || exit 0
[ -n "$meta" ] || exit 0

slug="$(printf '%s' "$meta" | jq -r '.started_slug')"
[ -n "$slug" ] || slug="$(date +%Y-%m-%d_%H%M)"
title_slug="$(printf '%s' "$meta" | jq -r '.title_slug')"
file="$dir/${slug}_${title_slug:+${title_slug}_}${root:0:8}.md"

# One writer per thread at a time (the Stop hooks of two sessions of one thread, or a Stop
# that overlaps the next turn's notes edit).
take_lock "$dir" "$root" || exit 0
trap 'release_lock "$dir" "$root"; rm -f "$last_msg_file"' EXIT

# The title can appear or change after the first reply: keep one file per thread.
old=""
for f in "$dir"/*_"${root:0:8}".md; do is_handoff_file "$f" && { old="$f"; break; }; done
if [ -n "$old" ] && [ "$old" != "$file" ]; then
  audit "$dir" "$sid" "rename" "$old -> $file"
  mv -f "$old" "$file"
fi

# The notes block: the sidecar is the source of truth; a file written by an older version
# seeds it once. The block in the file is only ever a copy.
notes_file="$(notes_sidecar "$dir" "$root")"
if [ ! -f "$notes_file" ] && [ -f "$file" ]; then
  notes_of "$file" > "$notes_file"
fi
notes_body=""
[ -f "$notes_file" ] && notes_body="$(sidecar_notes "$notes_file")"
[ -n "$notes_body" ] || notes_body="$NOTES_PLACEHOLDER"
notes="$NOTES_START
$notes_body
$NOTES_END"

# Compaction summaries of every session in the thread (written by save-compact.sh); the latest is shown.
compact_section=""
all_compact=""
while IFS= read -r m; do
  [ -n "$m" ] && [ -s "$st/${m:0:8}.compact.md" ] && all_compact="${all_compact}$(cat "$st/${m:0:8}.compact.md")
"
done <<< "$members"
if [ -n "$all_compact" ]; then
  count="$(printf '%s' "$all_compact" | grep -c '^### ')"
  latest="$(printf '%s' "$all_compact" | awk '/^### /{buf=""} {buf = buf $0 "\n"} END{printf "%s", buf}')"
  if [ "${#latest}" -gt "$summary_chars" ]; then
    latest="${latest:0:$summary_chars}
[... truncated at ${summary_chars} characters; full text in ${st}/<session>.compact.md]"
  fi
  compact_section="## Compaction summary (written by Claude Code)

_${count} compaction(s) in this thread; the latest is shown. Full texts: \`${st}/<session>.compact.md\`._

${latest}

"
fi

git_section=""
if [ -n "$branch" ]; then
  git_section="## Git

Branch: \`$branch\`

Working tree:
\`\`\`
${status:-clean}
\`\`\`

Recent commits:
\`\`\`
$log
\`\`\`

"
fi

# The three text blocks go in as jq arguments: no shell substitution touches user text
# (bash 5.2 would expand "&" in a ${var//…} replacement, bash 3.2 keeps quotes literally).
body="$(printf '%s' "$meta" | jq -r \
  --arg sid "$sid" --arg root "$root" --arg cwd "$cwd" --arg branch "$branch" \
  --arg thread "$thread_ids" --argjson nm "$n_members" --arg status "$status_line" \
  --arg notes "$notes" --arg compact "$compact_section" --arg git "$git_section" '
  def section(title; body): if (body | length) > 0 then "## " + title + "\n\n" + body + "\n\n" else "" end;
  def k(n): if n >= 1000000 then ((n / 100000 | floor) / 10 | tostring) + "M" elif n >= 1000 then ((n / 1000) | floor | tostring) + "k" else (n | tostring) end;
  def quote: "> " + gsub("\n"; "\n> ");
  "# Handoff: " + (if .title == "" then "untitled session" else .title end) + "\n\n"
  + "- Session: `" + $sid + "`\n"
  + (if $nm > 1 then "- Thread: " + $thread + " (" + ($nm | tostring) + " sessions in this file)\n" else "" end)
  + "- Project: `" + $cwd + "`\n"
  + (if $branch != "" then "- Branch: `" + $branch + "`\n" else "" end)
  + "- Started: " + .started + "\n"
  + "- Updated: " + .updated + "\n"
  + "- User turns: " + (.turns | tostring) + "\n"
  + "- Status: " + $status + "\n"
  + "<!-- handoff:root:" + $root + " -->\n"
  + "<!-- handoff:updated_epoch:" + (.updated_epoch | tostring) + " -->\n\n"
  + "## Notes (written by /handoff:notes)\n\n" + $notes + "\n\n"
  + $compact
  + section("Last reply from Claude"; (.replies | last // "" | quote))
  + section("Earlier replies, oldest first"; (.replies | .[:-1] | map(quote) | join("\n\n---\n\n")))
  + section("User requests, in order"; (.prompts | map("- `" + .t + "` " + .text) | join("\n")))
  + section("Files changed"; (.edited | map("- `" + . + "`") | join("\n")))
  + section("Files read"; (.read | map("- `" + . + "`") | join("\n")))
  + $git
  + "## Tokens\n\n"
  + "| API calls | Context now | Cold (cache writes) | Warm (cache reads) | Output |\n|---|---|---|---|---|\n"
  + "| " + (.tokens.calls | tostring) + " | " + k(.tokens.context) + " | " + k(.tokens.cold) + " | " + k(.tokens.warm) + " | " + k(.tokens.output) + " |\n\n"
  + (if .tokens.big_writes != "" then "Large cache writes (cold starts, skill loads, cache expiry): " + .tokens.big_writes + "\n\n" else "" end)
')"
[ -n "$body" ] || exit 0

# A member's transcript was deleted (Claude Code keeps them cleanupPeriodDays, 30 by default):
# the thread cannot be rebuilt from scratch, so the last full snapshot is appended as archive.
fz="$(frozen_file "$dir" "$root")"
if [ -n "$missing" ] && [ -s "$fz" ]; then
  archive=""
  for h in "Last reply from Claude" "Earlier replies, oldest first" "User requests, in order" "Files changed"; do
    part="$(section "$fz" "$h")"
    [ -n "$part" ] && archive="${archive}### ${h} (archived)

${part}

"
  done
  [ -n "$archive" ] && body="${body}## Archived history

_Transcripts of session(s) ${missing}are no longer on disk; this is the snapshot of the file taken ${missing:+$(date -r "$fz" '+%Y-%m-%d %H:%M' 2>/dev/null)}._

${archive}"
fi

tmp="$file.tmp.$$"
{
  printf '%s\n' "$body"
  printf '_Generated by the handoff plugin from the local transcript. No tokens were spent._\n'
} > "$tmp" && mv -f "$tmp" "$file" && cp -f "$file" "$dir/LATEST.md"
# Snapshot of a complete thread render, kept for the day a transcript disappears.
[ "$n_members" -gt 1 ] && [ -z "$missing" ] && cp -f "$file" "$fz"
release_lock "$dir" "$root"
trap 'rm -f "$last_msg_file"' EXIT

# Retention: keep the newest N thread files. Only handoff files are ever deleted, and only
# when the directory holds nothing else (a shared directory is left alone). State of sessions
# whose file is gone is dropped after a day, except snapshots and transcript pointers.
if [ "$keep" -gt 0 ] 2>/dev/null; then
  if [ -n "$(foreign_md_files "$dir")" ]; then
    audit "$dir" "$sid" "retention-skipped" "other markdown files in $dir"
  else
    session_files "$dir" | tail -n +"$((keep + 1))" | while IFS= read -r f; do
      is_handoff_file "$f" || continue
      audit "$dir" "$sid" "retention-rm" "$f"
      rm -f "$f"
    done
    find "$st" -type f -mtime +1 ! -name '*.frozen.md' ! -name '*.transcript' ! -name 'audit.log' -print0 2>/dev/null \
    | while IFS= read -r -d '' s; do
      sid8="$(basename "$s" | cut -d. -f1)"
      case "$sid8" in *[!0-9a-f]*|'') continue ;; esac
      [ -n "$(session_file_for "$dir" "$sid8")" ] || { audit "$dir" "$sid" "state-rm" "$s"; rm -f "$s"; }
    done
  fi
fi
exit 0
