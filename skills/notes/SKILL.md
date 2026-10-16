---
name: notes
description: Write the notes of the handoff file: goal, done, decisions and why, open questions, next action. Use before a long break, before /clear, or when the user asks to save progress or leave notes. Everything else in the file is already written by the hooks.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/scripts/handoff-path.sh" --notes)
---

# Handoff notes

The handoff plugin already writes a file for this session after every reply. Your job is to fill in the one block it cannot write itself.

1. Find the notes file of this session's thread:
   ```
   "${CLAUDE_PLUGIN_ROOT}/scripts/handoff-path.sh" --notes
   ```
   It prints a path under `.claude/handoffs/.state/` (created on first use). If the script says the session has no handoff file yet, say so and stop.

2. Write your notes into that file, replacing its content: plain markdown, no marker lines. The Stop hook copies it into the notes block of the handoff file after every reply. Use these headings, skip any that are empty:
   - **Goal**: what the user is trying to achieve, in one or two sentences.
   - **Done**: what is finished and verified (tests, runs), and what was not verified.
   - **In progress**: what is half-done and where it stands.
   - **Decisions**: each with the reason.
   - **Rejected**: options considered and why they were dropped, so the next session does not repeat them.
   - **Open questions / blockers**: what needs the user's answer or an external input.
   - **Next action**: one step that is startable without thinking: the file and line to open, or the exact command to run.
   - **Next steps**: the ordered list after that.
   - **Gotchas**: non-obvious facts about the code or environment learned in this session.

   Do not repeat what the file already captures automatically (the request list, file lists, git state, the compaction summary if there is one). Stay under about 60 lines. Never write secrets (keys, tokens, passwords) into the notes: the file is plain text on disk and is injected into later sessions.

3. Tell the user in one line that the notes are saved and will appear in the handoff file after this reply.
