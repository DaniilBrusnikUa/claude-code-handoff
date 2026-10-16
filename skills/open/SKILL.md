---
name: open
description: Open this session's handoff file in the default app, or print its path. Use when the user asks to open, see or find the handoff file.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/scripts/handoff-open.sh")
---

Run:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/handoff-open.sh"
```

It opens the file with the system's default app (macOS, Linux, Git Bash on Windows, WSL) and prints the path. Reply with the path in one line. If it fails, the session has no file yet; say so.
