#!/usr/bin/env bash
# Status-bar segment: reads Claude Code's statusLine JSON on stdin, prints one line.
# Use directly as the statusLine command, or call it from your own status script.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/handoff-status.sh" --short
