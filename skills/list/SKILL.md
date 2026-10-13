---
name: list
description: Show the handoff files of this project (recent Claude Code sessions) and let the user pick one to continue from with an arrow-key menu. Use when the user asks which sessions or handoffs exist here, or wants to choose one.
---

1. Run and show the output unchanged, as a code block:
   ```
   "${CLAUDE_PLUGIN_ROOT}/scripts/handoff-list.sh"
   ```
   If it prints nothing, say that no handoff exists in this project yet and stop.

2. Offer the choice with the AskUserQuestion tool (single select). One option per session, in the same order, label = `N. <started> <title>` shortened to fit, description = age, branch and the first notes line if any. The tool takes at most 4 options: with more sessions, offer the first 4 and say in the question that a number from the list can be typed under "Other". Put "Keep the current context" as the last option when fewer than 4 sessions exist. Say in the question that picking one makes this session continue in that file.

3. If the user picked a session (or typed a number), continue exactly as the `load` skill of this plugin describes, with that number:
   ```
   "${CLAUDE_PLUGIN_ROOT}/scripts/handoff-show.sh" --adopt <number>
   ```
   then the five-line summary (the scripts record the lineage themselves). If they chose to keep the current context, say so in one line and stop.
