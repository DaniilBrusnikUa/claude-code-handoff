<h1 align="center">claude-code-handoff</h1>

<p align="center"><b>Pick up a Claude Code session where you left it, without paying to replay it.</b></p>

<p align="center">
  <a href="https://github.com/DaniilBrusnikUa/claude-code-handoff/blob/main/LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="Claude Code plugin" src="https://img.shields.io/badge/Claude%20Code-plugin-8A2BE2">
  <img alt="zero tokens to write" src="https://img.shields.io/badge/tokens%20to%20write-0-success">
  <img alt="bash + jq" src="https://img.shields.io/badge/runtime-bash%20%2B%20jq-lightgrey">
</p>

```
claude plugin marketplace add DaniilBrusnikUa/claude-code-handoff
claude plugin install handoff@claude-code-handoff
```

Restart Claude Code once. That is the whole setup. It reads the transcript Claude Code already keeps in `~/.claude/projects/`, writes markdown into `<project>/.claude/handoffs/` (git-excluded, local only) and never uses the network. [Full disclosure](#what-it-runs-sends-and-fetches).

## The problem

Claude Code re-sends your whole conversation on every turn. For an hour after your last message that replay is nearly free, because the prompt cache serves it. After that the whole history is billed again, at double the normal input price. Come back from lunch to a long session with `claude --resume` and you pay for everything you said yesterday before you type a word. This plugin writes a **handoff file** for every session while you work, with shell scripts and no model call, and gives the next session that file instead of the replay.

Measured in one real session (Claude Fable 5.1, 1-hour cache; history 236k tokens; system prefix shared by every session 25k, prefix specific to this session 18k):

| Coming back after a break | What is paid | Input-equivalents | USD at API prices |
|---|---|---|---|
| `--resume`, cache warm (< 1 h) | 0.025 × 236k | 5.9k | 0.06 |
| **New session + handoff** | 2 × 18k + 0.025 × 25k + 2 × ~1k | ~38k | 0.38 |
| `--resume`, cache cold (> 1 h) | 2 × 212k + 0.025 × 25k | ~425k | 4.25 |

Rates are Fable 5.1's: cache read 0.025× the input price, 1-hour cache write 2×, $10 per million input tokens. Opus and Sonnet 5.5 read at 0.05×, older models at 0.1×; 5-minute cache writes cost 1.25×. The 25k system prefix was a warm read at every one of 17 session starts measured, so a fresh session wins once the history exceeds the session-specific prefix, about 20k tokens. Usage limits are drawn on every request for the whole context; Anthropic does not publish the weighting, so treat the dollar column as the upper bound of the ratio, not as your limit. In 10 days of the author's transcripts, 12 resumes after breaks of 45 minutes or more wrote 4.0M tokens cold, about $80 at API prices; with the handoff the same 12 restarts would have cost about 0.5M.

<p align="center"><img src="docs/session-start.svg" alt="A new session: the numbered list of recent sessions in the terminal, the user types 1, Claude joins that session's file and shows its header and notes" width="820"></p>

## First session

Three words you will meet:

- **Handoff file**: one markdown file per piece of work in `.claude/handoffs/`, rewritten after every reply.
- **Session list**: the numbered list of those files, printed in the terminal when Claude Code starts.
- **Notes**: the one part of the file Claude writes (goal, decisions, next action). Everything else is extracted from the transcript.

1. **Start.** Run `claude`. The session list appears (image above). Type a number to continue that work: Claude reads the file, answers in five lines, and this session writes into that file from now on. Type your task instead and you start new work; Claude still has the newest file's notes, last reply and compaction summary in context (1–4k tokens). If the previous session closed less than an hour ago, a tip says `claude -r <id>` is cheaper, since the cache is still warm. If the newest file was written on another branch, a note says so.
2. **Work.** After every reply the file is rewritten. Nothing to do.
3. **Status bar.** `handoff ● <title> · ctx 41%`. At 70% of the context, or 80% of the 5-hour limit, it adds `→ /handoff:notes`. [Setup](docs/INTERNALS.md#status-bar).
4. **Notes.** Before a long break, `/handoff:notes`: one turn, Claude writes goal, done, decisions and why, open questions, next action. Or set `CLAUDE_HANDOFF_AUTO_NOTES=context` and it happens by itself at 60% and 85% of the context window, right before that information would be compacted away.
5. **Compaction.** When Claude Code compacts the context, the summary it wrote is kept in the file.
6. **Exit.** Close the terminal or let the laptop sleep: the file is already current. It shows 🟢 while a session is open, ⚪ once closed.

## Commands

| Command | What it does |
|---|---|
| `/handoff:list` | The session list with an arrow-key menu to continue one. |
| `/handoff:load <n>` | Continue a session by number, id or part of its name; this session writes into its file from then on. Without an argument: the menu. |
| `/handoff:notes` | Claude writes the notes: goal, done, in progress, decisions and why, rejected options, open questions, next action, next steps, gotchas. One turn. |
| `/handoff:status` | Which file this session writes to, which sessions share it, which are open. |
| `/handoff:open` | Open that file in the default app and print its path. |

At start, type the number. Later, `/handoff:list` to pick, `/handoff:load <n>` if you already know which.

## The file

<p align="center"><img src="docs/handoff-file.svg" alt="A handoff file: title, Next line, header with thread and status, notes, last reply, tokens table" width="820"></p>

```
# Handoff: <title of the first session>
- Next: <the next action from the notes>
- Session / Thread (sessions sharing this file) / Project / Branch / Started / Updated / User turns
- Status: 🟢 in work (open: <ids>) | ⚪ saved (session closed <time>)

## Notes (written by /handoff:notes)            the only model-written part
## Last reply from Claude                       in full
## Earlier replies, oldest first                last four end-of-turn replies, shortened
## User requests, in order                      last 25 prompts, one line each
## Files changed / Files read
## Git                                          branch, working tree, last 5 commits
## Compaction summary (written by Claude Code)  the latest; all of them under .state/
## Tokens                                       per session: calls, cold / warm cache, output, input-equivalents, ≈ USD
## Archived history                             only when a transcript was deleted (see FAQ)
```

Files are named `<start date>_<time>_<title>_<id>.md`; `LATEST.md` is a copy of the most recently written one. Secrets of common shapes are redacted on the way in, see [Privacy](#privacy).

## Settings

Environment variables, in the `env` block of `~/.claude/settings.json` (all projects) or `.claude/settings.local.json` (one project). Four matter:

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_HANDOFF_IN_PROJECT` | `true` | `true`: `<project>/.claude/handoffs/`. `false`: `~/.claude/handoffs/<project>/`, nothing written inside the project. |
| `CLAUDE_HANDOFF_ROOT` | `cwd` | What counts as the project. `cwd`: the directory the session started in. `git`: the repository root, so sessions started in subfolders share one list. |
| `CLAUDE_HANDOFF_AUTOLOAD` | `compact` | What Claude gets at start. `compact`: notes, compaction summary, last reply, list. `full`: the whole file. `false`: nothing. |
| `CLAUDE_HANDOFF_AUTO_NOTES` | `0` | `context`: Claude updates the notes at 60% and 85% of the context window, one turn each, re-armed after a compaction. `N`: every N user turns. Most people want `context`. |

<details>
<summary>Advanced</summary>

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_HANDOFF_DIR` | unset | Explicit directory (absolute, `~/…`, or relative to the project); overrides the two above. Give it a directory of its own. |
| `CLAUDE_HANDOFF_HEADLESS` | unset | `true` runs the plugin in `claude -p` / SDK sessions too. |
| `CLAUDE_HANDOFF_KEEP` | `50` | Files kept per project (files, not days). Only handoff files are deleted, and only while the directory holds nothing else. 1–4 become 5; `0` disables. |
| `CLAUDE_HANDOFF_INDEX` | `5` | Sessions shown in the list at start. |
| `CLAUDE_HANDOFF_CONTEXT_CHARS` | `9500` | Max characters given to Claude at start (Claude Code caps hook output at 10,000; blocks shrink to fit). |
| `CLAUDE_HANDOFF_NUDGE_CONTEXT` / `_NUDGE_LIMIT` / `_NUDGE_LIMIT_HARD` / `_NUDGE_WEEK` | `70` / `80` / `95` / `90` | Status bar: context % for `→ /handoff:notes`; 5-hour usage % for the same; 5-hour % for `notes now`; 7-day % shown from. `0` disables one. |
| `CLAUDE_HANDOFF_AUTO_NOTES_AT` / `_CONTEXT_WINDOW` | `60,85` / auto | Auto-notes thresholds; window size, 200k or 1M depending on the largest request seen. |
| `CLAUDE_HANDOFF_RATE_READ` / `_RATE_WRITE` / `_RATE_OUTPUT` / `_PRICE_PER_M` | `0.025` / `2` / `5` / `10` | Factors of the Tokens table (cache read, cache write, output, USD per million input-equivalents). |
| `CLAUDE_HANDOFF_COMPACT_CHARS` / `_LOAD_CHARS` | `3000` / `16000` | Max characters per block in `compact` mode; max in `full` mode. |
| `CLAUDE_HANDOFF_COMPACT_SUMMARY_CHARS` | `6000` | Max characters of the compaction summary kept in the file. |
| `CLAUDE_HANDOFF_MAX_PROMPTS` / `_PROMPT_CHARS` | `25` / `400` | User requests kept; characters per request. |
| `CLAUDE_HANDOFF_MAX_REPLIES` / `_REPLY_CHARS` / `_SHORT_REPLY_CHARS` | `5` / `4000` / `800` | Replies kept; characters of the newest; of each older one. |

</details>

Example, central storage for every project: `{ "env": { "CLAUDE_HANDOFF_IN_PROJECT": "false" } }`.

## What it runs, sends and fetches

Hooks run the bash scripts in `scripts/` with `jq` and `git` from your PATH. They read the session transcript under `~/.claude/projects/`, the hook's stdin JSON, and `git` state of the project; they write markdown files and small state files under the handoff directory, a line in the clone's `.git/info/exclude`, and nothing else. `/handoff:open` runs `open` (macOS) or `xdg-open` (Linux) on the handoff file. No network access, no telemetry, no package installs, no credentials read or sent, no changes to Claude Code settings or permissions. The one model-written part, the notes, happens only when you run `/handoff:notes` or set `CLAUDE_HANDOFF_AUTO_NOTES`. The event-by-event description is in [docs/INTERNALS.md](docs/INTERNALS.md).

## Privacy

Everything is local: the scripts read `~/.claude/projects/` and write markdown next to your project. Requests and replies are copied as text, so `scripts/scrub.jq` redacts common secret shapes: API keys (`sk-…`, `sk_live_…`, AWS, Google, GitHub, GitLab, Slack), JWTs, bearer tokens, private keys, credentials in URLs and `password=` / `token=` / `*_secret_*=` style values, in replies, requests, summaries, the notes and the git section. A guard against accidental leaks, not a guarantee: review a file before sharing it, and keep secrets out of the notes. The directory is added to the clone's `.git/info/exclude`, which is local and never committed. If the directory is committed anyway, the plugin stops writing there and says so at start.

## Compared to

| | claude-code-handoff | `claude --resume` | memory plugins that summarize with a model |
|---|---|---|---|
| Tokens to save progress | 0 | 0 | a model call per save |
| Cost of coming back after the cache expired | session prefix + 1–4k tokens | the whole history, cold, at 2× | prefix + their summary |
| Survives a killed terminal | yes, written after every reply | yes | depends on the hook used |
| Knows when resuming is cheaper | yes, says so at start; warns on a cold resume | n/a | no |
| Several sessions in one file | yes | no | varies |
| Shows cold starts, cache usage, ≈ cost | per session and per file | no | no |
| Dependencies | bash, jq, git | none | often Node or Python |

The plugin does not replace `--resume`: within the hour, resuming is the cheapest option, and the start tip tells you so. Compared to `/compact` plus a CLAUDE.md: compaction keeps one summary inside one session, the handoff keeps every session's history and notes on disk, readable without Claude, and costs nothing to update.

## FAQ

**Does it change anything in my repository?** No. Files go to `.claude/handoffs/`, excluded through `.git/info/exclude`, which is per-clone and never committed. Set `CLAUDE_HANDOFF_IN_PROJECT=false` to keep files outside the project entirely. If someone did commit the directory, the plugin refuses to write into tracked files and tells you at start.

**Why is there a file I did not ask for?** Every interactive session writes one after its first reply. It is replaced, not accumulated: one file per piece of work, the newest 50 kept.

**I typed a number (or used `/handoff:load`), where did this session's own file go?** It joined that session's file; its history is there now. A separate file would duplicate it. If other sessions had joined this session's file, it stays and they move along.

**What happens after Claude Code deletes old transcripts?** Claude Code keeps transcripts `cleanupPeriodDays` (30 by default). A single-session file is never rewritten after its session ended, so it keeps its content. A file shared by several sessions is rewritten by each of them, so the plugin keeps a snapshot of the last complete render in `.state/`; when a transcript is gone, the snapshot is appended as `## Archived history`.

**Why isn't the notes block written automatically?** Everything a script can know is already automatic. The notes need judgment (what mattered, what was rejected, what comes next), and that is a model turn. Run `/handoff:notes` when it is worth it, or set `CLAUDE_HANDOFF_AUTO_NOTES=context`.

**Two terminals in the same project?** Each session has its own file unless it joined another. The list shows both and marks the open one; the start says when the newest one is still open elsewhere.

**Windows?** Untested. The scripts are plain bash + jq; Git Bash or WSL should work. Reports welcome.

## Uninstall

`claude plugin uninstall handoff@claude-code-handoff` (or remove it in `/plugin`). Nothing else runs afterwards. What stays, and how to remove it:

- `.claude/handoffs/` in each project (the handoff files, `LATEST.md`, `.state/`): delete the directory.
- The line `/.claude/handoffs/` in the clone's `.git/info/exclude`: delete it if you want.
- `~/.claude/handoffs/` when `CLAUDE_HANDOFF_IN_PROJECT=false` was used.
- `CLAUDE_HANDOFF_*` entries in the `env` block and the `statusLine` entry of `~/.claude/settings.json`, if you added them.

## Requirements

`bash` (3.2 or newer), `jq` 1.6 or newer, `git`. Present on macOS and most Linux distributions.

## Development

```
git clone https://github.com/DaniilBrusnikUa/claude-code-handoff
claude --plugin-dir /path/to/claude-code-handoff
```

Every script accepts the hook's JSON on stdin, so they can be tested without a session:

```
jq -nc '{session_id:"abc", transcript_path:"/path/to/session.jsonl", cwd:"/path/to/project"}' | scripts/save-handoff.sh
```

`tests/run.sh` runs 89 checks on synthetic fixtures in a temp directory (render stability, notes markers, retention guard, thread join, start screen, status line, secret scrubbing). The images in `docs/` are rendered from real plugin output with `docs/render-terminal.py`. How the hooks, state files and threads work: [docs/INTERNALS.md](docs/INTERNALS.md).

See [CHANGELOG.md](CHANGELOG.md). Issues and pull requests welcome.

## License

MIT
