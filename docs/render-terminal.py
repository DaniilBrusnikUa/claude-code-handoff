#!/usr/bin/env python3
"""Render captured plugin output as a terminal-looking SVG for the README (no screenshots needed)."""
import html, sys

def render(src, dst, title, width=120, max_lines=None, cut=98):
    lines = open(src, encoding="utf-8").read().splitlines()
    out, blank = [], False
    for l in lines:                      # squeeze blank runs
        if not l.strip():
            if blank: continue
            blank = True
        else:
            blank = False
        out.append(l)
    lines = out
    if cut:
        lines = [l[:cut] + (" …" if len(l) > cut else "") for l in lines]
    if max_lines and len(lines) > max_lines:
        lines = lines[:max_lines] + ["…"]
    cw, lh, pad = 7.8, 19, 16
    w = int(width * cw + 2 * pad)
    h = int(len(lines) * lh + 2 * pad + 36)
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" font-family="SFMono-Regular, Menlo, Consolas, \'Liberation Mono\', monospace" font-size="13">',
           f'<rect width="{w}" height="{h}" rx="10" fill="#1e1f22"/>',
           f'<rect width="{w}" height="36" rx="10" fill="#2b2d31"/><rect y="20" width="{w}" height="16" fill="#2b2d31"/>',
           '<circle cx="18" cy="18" r="6" fill="#ff5f57"/><circle cx="38" cy="18" r="6" fill="#febc2e"/><circle cx="58" cy="18" r="6" fill="#28c840"/>',
           f'<text x="{w/2}" y="23" text-anchor="middle" fill="#9aa0a6" font-size="12">{html.escape(title)}</text>']
    y = 36 + pad + 13
    for l in lines:
        color = "#e3e3e3"
        if l.startswith("#"): color = "#8ab4f8"
        elif l.startswith(">"): color = "#c3e88d"
        elif l.startswith("Note for the user") or l.startswith("Handoff from"): color = "#f5d87a"
        elif l.startswith("- `") or l.startswith("- Session") or l.startswith("- Thread") or l.startswith("- Status"): color = "#e3e3e3"
        elif l.startswith("_") or l.startswith("<!--"): color = "#8d8d8d"
        svg.append(f'<text x="{pad}" y="{y}" fill="{color}" xml:space="preserve">{html.escape(l)}</text>')
        y += lh
    svg.append("</svg>")
    open(dst, "w", encoding="utf-8").write("\n".join(svg))
    print(dst, len(lines), "lines")

if __name__ == "__main__":
    base = sys.argv[1]
    render(f"{base}/start.txt", "docs/session-start.svg", "claude — new session, what the plugin injects at start")
    render(f"{base}/list.txt", "docs/list.svg", "/handoff:list")
    render(f"{base}/status.txt", "docs/statusline.svg", "status line")
    render(f"{base}/file.txt", "docs/handoff-file.svg", ".claude/handoffs/2026-10-12_1114_Rate-limiter-with-Redis-fallback_8f3c21aa.md", max_lines=48)
