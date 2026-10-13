---
name: notes
description: Record decisions, open questions and next steps for the next Claude Code session. Use before a long break, before /clear, or when the user asks to save progress, write a handoff, or leave notes for later. The automatic part (requests, replies, files, git) is already captured by the plugin's Stop hook; this skill adds the judgment that only the model has.
---

# Handoff notes

The handoff plugin already writes a file for this session after every reply. Your job is to fill in the one block it cannot write itself.

1. Find the file:
   ```
   "${CLAUDE_PLUGIN_ROOT}/scripts/handoff-path.sh"
   ```
   If that variable is not expanded in your context, the file is the newest `*.md` other than `LATEST.md` under `.claude/handoffs/` in the project (or under `~/.claude/handoffs/<project-slug>/` when `CLAUDE_HANDOFF_IN_PROJECT=false`). If no file exists yet, say so and stop.

2. Replace everything between `<!-- handoff:notes:start -->` and `<!-- handoff:notes:end -->` with your notes. Keep both marker lines; the Stop hook preserves this block on later rewrites. Use these headings, skip any that are empty:
   - **Goal**: what the user is trying to achieve, in one or two sentences.
   - **State**: what is done, what is in progress, what was verified (tests, runs) and what was not.
   - **Decisions**: each with the reason.
   - **Rejected**: options considered and why they were dropped, so the next session does not repeat them.
   - **Open questions / blockers**: what needs the user's answer or an external input.
   - **Next steps**: concrete and ordered; the first one should be startable without further thought.
   - **Gotchas**: non-obvious facts about the code or environment learned in this session.

   Do not repeat what the file already captures automatically (the request list, file lists, git state, the compaction summary if there is one). Stay under about 60 lines.

3. Copy the file over `LATEST.md` in the same directory so the next session loads the notes immediately.

4. Tell the user the file path in one line.
