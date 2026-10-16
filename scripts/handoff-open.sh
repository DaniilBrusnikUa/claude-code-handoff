#!/usr/bin/env bash
# Opens the current session's handoff file in the default application and prints the path.
#   macOS: open · Linux: xdg-open · Git Bash / MSYS / Cygwin: cmd.exe start · WSL: wslview or explorer.exe
# Without an opener it only prints the path.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
f="$("$HERE/handoff-path.sh" "$@")" || exit 1
case "$(uname -s 2>/dev/null)" in
  Darwin)
    command -v open >/dev/null 2>&1 && open "$f" ;;
  MINGW*|MSYS*|CYGWIN*)
    # `start` is a cmd.exe builtin; the first quoted argument is the window title. MSYS would
    # rewrite /c as C:\, hence the conversion is switched off for this one call.
    w="$f"; command -v cygpath >/dev/null 2>&1 && w="$(cygpath -w "$f" 2>/dev/null || printf '%s' "$f")"
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' cmd.exe /c start "" "$w" >/dev/null 2>&1 ;;
  *)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      if command -v wslview >/dev/null 2>&1; then wslview "$f" >/dev/null 2>&1
      elif command -v explorer.exe >/dev/null 2>&1; then explorer.exe "$(wslpath -w "$f" 2>/dev/null || printf '%s' "$f")" >/dev/null 2>&1
      fi
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$f" >/dev/null 2>&1
    fi ;;
esac
printf '%s\n' "$f"
