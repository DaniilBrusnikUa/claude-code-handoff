#!/usr/bin/env bash
# Self-contained checks for the hook scripts. Runs on synthetic fixtures in a temp
# directory; nothing outside it is touched. Usage: tests/run.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/../scripts"
T="$(mktemp -d "${TMPDIR:-/tmp}/handoff-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export CLAUDE_CODE_SESSION_ATTENDED=1
unset CLAUDE_HANDOFF_DIR CLAUDE_HANDOFF_KEEP CLAUDE_HANDOFF_IN_PROJECT CLAUDE_HANDOFF_ROOT CLAUDE_PROJECT_DIR
fail=0; pass=0
ok()   { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

A="aaaaaaaa-1111-4111-8111-111111111111"
B="bbbbbbbb-2222-4222-8222-222222222222"
C="cccccccc-3333-4333-8333-333333333333"
proj="$T/project"; mkdir -p "$proj"
dir="$proj/.claude/handoffs"

# A transcript: one prompt, one reply quoting the notes marker and a secret, one prompt with
# an attachment (array content), one tool result (not a prompt), usage on the assistant rows.
transcript() {  # <session id> <file>
  cat > "$2" <<EOF
{"type":"user","sessionId":"$1","timestamp":"2026-01-02T10:00:00.000Z","message":{"role":"user","content":"first request"}}
{"type":"assistant","sessionId":"$1","timestamp":"2026-01-02T10:00:05.000Z","requestId":"r1","message":{"role":"assistant","content":[{"type":"text","text":"Reply one. The block sits between <!-- handoff:notes:start --> and <!-- handoff:notes:end --> lines. Also AWS_SECRET_ACCESS_KEY=abcdefgh1234 and ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"}],"usage":{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_read_input_tokens":20000,"output_tokens":50}}}
{"type":"user","sessionId":"$1","timestamp":"2026-01-02T10:01:00.000Z","message":{"role":"user","content":[{"type":"text","text":"[Image #1] second request with a picture"}]}}
{"type":"assistant","sessionId":"$1","timestamp":"2026-01-02T10:01:02.000Z","requestId":"r2","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}],"usage":{"input_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":21000,"output_tokens":20}}}
{"type":"user","sessionId":"$1","timestamp":"2026-01-02T10:01:03.000Z","message":{"role":"user","content":[{"type":"tool_result","content":"files"}]}}
{"type":"assistant","sessionId":"$1","timestamp":"2026-01-02T10:01:05.000Z","requestId":"r3","message":{"role":"assistant","content":[{"type":"text","text":"Reply two & done."}],"usage":{"input_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":21100,"output_tokens":30}}}
{"type":"ai-title","sessionId":"$1","aiTitle":"Test\u0007 thread: one/two"}
EOF
}
hook() {  # <session id> <transcript> -> runs save-handoff.sh as the Stop hook would
  jq -nc --arg s "$1" --arg t "$2" --arg c "$proj" '{session_id:$s, transcript_path:$t, cwd:$c, last_assistant_message:"Reply two & done."}' | "$S/save-handoff.sh"
}

# ---- 1. render twice: same size, notes clean, prompts counted, secrets gone ----------
transcript "$A" "$T/a.jsonl"
hook "$A" "$T/a.jsonl"
fa="$(ls "$dir"/*_aaaaaaaa.md 2>/dev/null | head -1)"
check "file written with a clean name" '[ -n "$fa" ] && [ "$(basename "$fa")" = "2026-01-02_1100_Test-thread-one-two_aaaaaaaa.md" -o "$(basename "$fa")" = "$(basename "$fa" | grep -E "^2026-01-02_[0-9]{4}_Test-thread-one-two_aaaaaaaa\.md$")" ]'
s1="$(wc -c < "$fa")"
hook "$A" "$T/a.jsonl"; hook "$A" "$T/a.jsonl"
s3="$(wc -c < "$fa")"
check "size constant across renders ($s1 -> $s3)" '[ "$s1" = "$s3" ]'
check "exactly one start marker" '[ "$(grep -c "^<!-- handoff:notes:start -->$" "$fa")" = 1 ]'
check "quoted marker neutralised" 'grep -q "handoff‑notes:start" "$fa"'
check "notes still the placeholder" 'grep -q "^_No notes yet" "$fa"'
check "User turns counts the array prompt" 'grep -q "^- User turns: 2$" "$fa"'
check "array prompt text shown" 'grep -q "second request with a picture" "$fa"'
check "AWS secret redacted" '! grep -q "abcdefgh1234" "$fa"'
check "github token redacted" '! grep -q "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" "$fa"'
check "ampersand survives the substitution" 'grep -q "Reply two & done" "$fa"'
check "cwd sidecar written" '[ "$(cat "$dir/.state/aaaaaaaa.cwd")" = "$proj" ]'

# ---- 2. notes sidecar is the source of truth ----------------------------------------
printf '**Goal**: test notes\n<!-- handoff:notes:start -->\n**Next**: keep going\n' > "$dir/.state/aaaaaaaa.notes.md"
hook "$A" "$T/a.jsonl"
check "notes from the sidecar rendered" 'grep -q "^\*\*Goal\*\*: test notes$" "$fa" && grep -q "^\*\*Next\*\*: keep going$" "$fa"'
check "marker pasted into the sidecar dropped" '[ "$(grep -c "^<!-- handoff:notes:start -->$" "$fa")" = 1 ]'
sn1="$(wc -c < "$fa")"; hook "$A" "$T/a.jsonl"
check "size constant with notes" '[ "$sn1" = "$(wc -c < "$fa")" ] && [ "$(grep -c "test notes" "$fa")" = 1 ]'

# ---- 3. a bloated block from an older version heals and seeds the sidecar -------------
transcript "$B" "$T/b.jsonl"
hook "$B" "$T/b.jsonl"
fb="$(ls "$dir"/*_bbbbbbbb.md | head -1)"
rm -f "$dir/.state/bbbbbbbb.notes.md"
# simulate the old bug: the block runs into the body
awk -v s="<!-- handoff:notes:start -->" '
  $0 == "<!-- handoff:notes:end -->" && !done { print "**Goal**: real notes"; print "## Last reply from Claude"; print "> junk " s; done = 1; next } { print }' "$fb" > "$fb.tmp" && mv "$fb.tmp" "$fb"
hook "$B" "$T/b.jsonl"
check "healed notes keep the real line" '[ "$(cat "$dir/.state/bbbbbbbb.notes.md")" = "**Goal**: real notes" ]'
check "healed file has one block" '[ "$(grep -c "^<!-- handoff:notes:start -->$" "$fb")" = 1 ] && ! grep -q "> junk" "$fb"'

# ---- 4. retention touches only handoff files, and nothing in a shared directory -------
export CLAUDE_HANDOFF_KEEP=5
for i in 1 2 3 4 5 6 7; do
  printf '# Handoff: old %s\n\n- Session: `%s`\n<!-- handoff:updated_epoch:1 -->\n\n## Notes\n' "$i" "dddddd0$i-4444-4444-8444-444444444444" > "$dir/2026-01-01_000${i}_old_dddddd0${i}.md"
  touch -t "20260101000$i" "$dir/2026-01-01_000${i}_old_dddddd0${i}.md"
done
printf '# my notes\n' > "$dir/README.md"; touch -t 202501010000 "$dir/README.md"
hook "$A" "$T/a.jsonl"
check "shared directory: nothing deleted" '[ "$(ls "$dir"/2026-01-01_*_old_*.md | wc -l | tr -d " ")" = 7 ] && [ -f "$dir/README.md" ]'
check "shared directory: skip logged" 'grep -q "retention-skipped" "$dir/.state/audit.log"'
rm -f "$dir/README.md"
printf '# Handoff: fake\n' > "$dir/2026-01-01_0000_nomarker_eeeeeeee.md"; touch -t 202501010000 "$dir/2026-01-01_0000_nomarker_eeeeeeee.md"
hook "$A" "$T/a.jsonl"
check "retention keeps a file without the epoch marker (shared dir again)" '[ -f "$dir/2026-01-01_0000_nomarker_eeeeeeee.md" ]'
rm -f "$dir/2026-01-01_0000_nomarker_eeeeeeee.md"
hook "$A" "$T/a.jsonl"
n_old="$(ls "$dir"/2026-01-01_*_old_*.md 2>/dev/null | wc -l | tr -d ' ')"
check "retention keeps 5 newest handoff files (old left: $n_old)" '[ "$n_old" = 3 ] && [ -f "$fa" ] && [ -f "$fb" ]'
check "retention logged" 'grep -q "retention-rm" "$dir/.state/audit.log"'
unset CLAUDE_HANDOFF_KEEP
check "LATEST.md kept" '[ -f "$dir/LATEST.md" ]'

# ---- 5. --adopt: numbers from the saved index; a root with members is kept ------------
export CLAUDE_CODE_SESSION_ID="$C"
transcript "$C" "$T/c.jsonl"; hook "$C" "$T/c.jsonl"
fc="$(ls "$dir"/*_cccccccc.md | head -1)"
"$S/handoff-list.sh" "$proj" > "$T/list.txt"
check "list prints root ids" 'grep -q "id cccccccc" "$T/list.txt" && grep -q "id aaaaaaaa" "$T/list.txt"'
check "index saved for the session" '[ -s "$dir/.state/cccccccc.index" ]'
nA="$(grep -n "_aaaaaaaa.md" "$T/list.txt" | cut -d: -f1 | head -1)"
touch "$fb"   # another session writes: the order changes, the number must not
out="$("$S/handoff-show.sh" --adopt "$nA" "$proj" 2>"$T/err.txt")"
check "adopt by number joins the file the list showed" 'grep -q "joined thread aaaaaaaa" "$T/err.txt"'
check "own single-session file removed and logged" '[ ! -f "$fc" ] && grep -q "adopt-rm" "$dir/.state/audit.log"'
check "member recorded" 'grep -q "^$C$" "$dir/.state/aaaaaaaa.members"'
# C is now in A. Make B a member of C's old id? Instead: A (root with member C) adopts B: must keep A's file.
export CLAUDE_CODE_SESSION_ID="$A"
rm -f "$dir/.state/aaaaaaaa.index"
"$S/handoff-show.sh" --adopt "bbbbbbbb" "$proj" >/dev/null 2>"$T/err2.txt"
check "root with members: file kept" '[ -f "$fa" ] && grep -q "kept" "$T/err2.txt" && grep -q "adopt-keep" "$dir/.state/audit.log"'
[ "$fail" = 0 ] || { echo "--- err2:"; cat "$T/err2.txt"; echo "--- audit:"; cat "$dir/.state/audit.log"; ls "$dir" "$dir/.state"; }
check "members follow into the new thread" 'grep -q "^$C$" "$dir/.state/bbbbbbbb.members" && [ "$(cat "$dir/.state/cccccccc.adopt")" = "$B" ]'
unset CLAUDE_CODE_SESSION_ID

# ---- 6. closed mark beats a late Stop ------------------------------------------------
jq -nc --arg s "$B" --arg c "$proj" '{session_id:$s, cwd:$c}' | "$S/mark-closed.sh"
check "closed mark written" '[ -s "$dir/.state/bbbbbbbb.closed" ]'
printf '%s' "$(( $(date +%s) + 5 ))" > "$dir/.state/bbbbbbbb.closed"   # SessionEnd after this Stop started
hook "$B" "$T/b.jsonl"
check "late Stop does not re-open" '[ ! -f "$dir/.state/bbbbbbbb.open" ] && ! grep "^- Status:" "$fb" | grep -q bbbbbbbb'

# ---- 7. settings validation, ids, lock ----------------------------------------------
CLAUDE_HANDOFF_MAX_PROMPTS="abc" hook "$A" "$T/a.jsonl"
check "non-integer setting falls back (file still written)" '[ "$(find "$fa" -newer "$T/list.txt" | wc -l | tr -d " ")" = 1 ]'
printf 'zz/../..' > "$dir/.state/aaaaaaaa.adopt"
. "$S/lib.sh"
check "invalid adopt id ignored" '[ "$(thread_root "$dir" "$A")" = "$A" ]'
rm -f "$dir/.state/aaaaaaaa.adopt"
mkdir -p "$dir/.state/aaaaaaaa.lock"; date +%s > "$dir/.state/aaaaaaaa.lock/t"
check "fresh lock blocks (times out)" '! take_lock "$dir" "$A"'
printf '1' > "$dir/.state/aaaaaaaa.lock/t"
check "stale lock is taken over" 'take_lock "$dir" "$A" && release_lock "$dir" "$A"'
check "--version prints a version" '"$S/save-handoff.sh" --version | grep -Eq "^[0-9]+\.[0-9]+"'
check "project slug percent-encodes" '[ "$(project_slug "/a b/c-d")" = "a%20b%2Fc-d" ]'

# ---- 8. scrub patterns -----------------------------------------------------------
sc="$(jq -n -L "$S" 'include "scrub"; "AWS_SECRET_ACCESS_KEY=abcdefgh1234 \"password\": \"hunter22\" github_pat_ABCDEFGHIJKLMNOPQRSTUVWXYZ1234 sk_live_ABCDEFGHIJ1234 AIzaSyA1234567890abcdefghijklmnopqrstuv glpat-ABCDEFGHIJKLMNOPQRST postgres://bob:pw123@db x-api-key: aaaaaaaa keep=this" | scrub')"
for v in abcdefgh1234 hunter22 ABCDEFGHIJKLMNOPQRSTUVWXYZ1234 sk_live_ABCDEFGHIJ1234 AIzaSyA1234567890 glpat-ABCDEFGHIJ bob:pw123 "x-api-key: aaaaaaaa"; do
  check "scrub hides '$v'" '! printf "%s" "$sc" | grep -qF "$v"'
done
check "scrub keeps ordinary text" 'printf "%s" "$sc" | grep -qF "keep=this"'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
