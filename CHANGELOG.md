# Changelog

## 0.4.0 — 2026-10-14
- Notes: markers count only as whole lines and the block ends at the first end marker; markers quoted in replies are neutralised; bloated blocks heal on the next render (#1). Notes live in `.state/<root>.notes.md`, the file shows a copy; `/handoff:notes` writes the sidecar (`handoff-path.sh --notes`) (#6).
- Deletes and renames touch only files named like a handoff and carrying the epoch marker; retention is skipped while other markdown files share the directory; `.frozen.md` and `.transcript` sidecars are never cleaned up (#2, #12).
- `/handoff:load` keeps a file that other sessions joined and moves those sessions along; `.state/audit.log` records every delete, rename and join (#3, #23).
- Numbers in the list are fixed at print time (`.state/<sid>.index`); the index shows the thread root id; ids and names match on the file name (#4, #5).
- Per-thread render lock; SessionEnd writes `.closed` so a late Stop does not re-open the session; no cache hint while a file is less than a minute old (#6, #7).
- Prompts with attachments (array content) are counted and shown (#8).
- scrub: `AWS_SECRET_ACCESS_KEY=`, `github_pat_`, `sk_live_`, `AIza…`, `glpat-`, JSON-quoted keys, credentials in URLs; the git section is scrubbed too (#9).
- Portability and hardening: quoted `${var//…}` replacements (bash 5.2 `&`), integer settings validated, `KEEP` raised to at least 5, the final reply passed through a file, control characters stripped from titles, ids validated before use in paths, `find -print0`, percent-encoded project slugs, physical paths for `.git/info/exclude`, headless detection scans 20 lines (#10, #13–#20).
- Skills resolve the project from the session's recorded cwd, not from the Bash tool's current directory (#11).
- Start context says which part is data and which is the instruction (#21). README: token estimate, statusline path without a version, Uninstall section; `save-handoff.sh --version`; `tests/run.sh` (#22, #23).

## 0.3.2 — 2026-10-14
- The start index is printed in the terminal (hook `systemMessage`, no tokens), so the number to type is visible; the handoff itself goes to Claude as `additionalContext`.

## 0.3.1 — 2026-10-14
- A bare number as the first message continues that thread from the start index (`new` starts fresh): no `/handoff:list`, no menu, no extra request.

## 0.3.0 — 2026-10-13
- Silent in `claude -p` / SDK sessions: no files, no context injected.
- Per-session open marks: a thread file stays 🟢 while any of its sessions is open.
- Snapshot of complete thread renders; appended as `## Archived history` when a transcript was deleted.
- Handoff directory added to the clone's `.git/info/exclude`.
- Status bar segment (`scripts/statusline.sh`), `/handoff:status`, `/handoff:open`.
- Start hint distinguishes "still open in another terminal" from "closed, cache warm".

## 0.2.x — 2026-10-13
- Threads: `/handoff:load` joins the chosen file instead of creating a new one; all sessions of a thread render into the root's file.
- Slash commands and the post-compaction continuation message are no longer counted as user requests.

## 0.1.x — 2026-10-13
- Per-session handoff files written by a `Stop` hook; compact autoload at `SessionStart`.
- Compaction summaries captured from `PostCompact`.
- Session index, warm-cache hint, secret redaction, retention, token accounting.
- `/handoff:list` with an arrow-key menu, `/handoff:load`, `/handoff:notes`.
- Final reply taken from the hook's `last_assistant_message` (fixes a race with the transcript).
