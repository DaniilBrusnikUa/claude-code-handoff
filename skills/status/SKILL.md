---
name: status
description: Show which handoff file this session writes to, its thread (sessions sharing the file), status and which sessions are open now. Use when the user asks where the handoff is being written, whether it is working, or what the current thread is.
---

Run and show the output as a code block:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/handoff-status.sh"
```

Add one line of explanation only if something looks off (no file yet, stale open marks, status ⚪ while working).
