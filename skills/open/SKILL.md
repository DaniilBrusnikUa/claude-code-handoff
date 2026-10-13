---
name: open
description: Open the current session's handoff file in the editor / default app, or show its path. Use when the user asks to open, see or find the handoff file of this session.
---

Run:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/handoff-open.sh"
```

It opens the file (macOS `open`, Linux `xdg-open`) and prints the path. Reply with the path in one line. If it fails, the session has no file yet; say so.
