# Changelog

## Unreleased
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
