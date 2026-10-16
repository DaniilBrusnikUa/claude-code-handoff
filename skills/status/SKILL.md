---
name: status
description: Show which handoff file this session writes to, which sessions share it, its status and which of them are open now. Use when the user asks where the handoff is written or whether it is working.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/scripts/handoff-status.sh")
---

Run and show the output as a code block:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/handoff-status.sh"
```

Add one line of explanation only if something looks off (no file yet, stale open marks, status ⚪ while working).
