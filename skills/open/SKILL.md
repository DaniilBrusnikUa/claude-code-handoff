---
name: open
description: Open this session's handoff file in the default app, or print its path. Use when the user asks to open, see or find the handoff file.
---

Run:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/handoff-open.sh"
```

It opens the file (macOS `open`, Linux `xdg-open`) and prints the path. Reply with the path in one line. If it fails, the session has no file yet; say so.
