# Shared jq definitions: secret redaction and the shape of a user prompt.

# Redacts common secret shapes from text that is copied into the handoff file, and
# neutralises the notes markers (a marker quoted in a reply must not open the notes block).
def scrub:
  gsub("-----BEGIN[A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END[A-Z ]*PRIVATE KEY-----"; "[redacted private key]")
  | gsub("eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}"; "[redacted jwt]")
  | gsub("sk-(ant-)?[A-Za-z0-9_-]{16,}"; "[redacted key]")
  | gsub("sk_(live|test)_[A-Za-z0-9]{10,}"; "[redacted stripe key]")
  | gsub("AKIA[0-9A-Z]{16}"; "[redacted aws key]")
  | gsub("AIza[0-9A-Za-z_-]{35}"; "[redacted google key]")
  | gsub("gh[pousr]_[A-Za-z0-9]{30,}"; "[redacted github token]")
  | gsub("github_pat_[A-Za-z0-9_]{20,}"; "[redacted github token]")
  | gsub("glpat-[A-Za-z0-9_-]{20,}"; "[redacted gitlab token]")
  | gsub("xox[abprs]-[A-Za-z0-9-]{10,}"; "[redacted slack token]")
  | gsub("(?<p>://)[^/\\s:@]+:[^@\\s/]+@"; "\(.p)user:[redacted]@")
  | gsub("(?<k>(?i)bearer\\s+)[A-Za-z0-9._~+/=-]{16,}"; "\(.k)[redacted]")
  | gsub("(?<k>(?i)[\"']?[A-Za-z0-9_.-]*(api[_-]?key|secret|token|password|passwd|access[_-]?key|private[_-]?key|authorization)[A-Za-z0-9_.-]*[\"']?\\s*[:=]\\s*[\"']?)[^\\s\"',]{6,}"; "\(.k)[redacted]")
  | gsub("<!-- handoff:"; "<!-- handoff‑");

# The text of a user entry: a plain string, or the text blocks of an array (prompts with an
# attachment arrive as arrays).
def prompt_text:
  (.message.content // "")
  | if type == "string" then .
    elif type == "array" then (map(select(type == "object" and .type == "text") | .text // "") | join(" "))
    else "" end;

# A user request: typed text, not a tool result, not a slash command, not a skill
# invocation, not the continuation message Claude Code inserts after compaction.
def is_prompt:
  (.type == "user" and .isMeta != true and .isCompactSummary != true
   and ((.message.content | type) == "string"
        or ((.message.content | type) == "array" and ((.message.content | any(type == "object" and .type == "tool_result")) | not)))
   and (prompt_text | length) > 0
   and (prompt_text | test("^\\s*<(command-name|command-message|local-command)") | not)
   and (prompt_text | test("^\\s*/[A-Za-z][A-Za-z0-9:_-]*\\s*$") | not));
