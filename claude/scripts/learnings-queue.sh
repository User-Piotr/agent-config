#!/usr/bin/env bash
# ~/.claude/scripts/learnings-queue.sh
#
# SessionEnd hook. Queues a learnings proposal for the repository the session
# ran in, then returns immediately.
#
# Why the work happens in a detached child rather than here: SessionEnd hooks
# share a 1.5 s budget (raised to the per-hook timeout, at most 60 s), and
# SessionEnd stdout never reaches the model — by then there is no turn left to
# inject into. So the session that is ending cannot summarise itself. A
# headless `claude -p` does it in the background instead and appends a dated
# entry to .claude/claude-md-review.md.
#
# Nothing here touches AGENTS.md or CLAUDE.md. The proposal sits in the review
# file until a human applies it; learnings-pending.sh surfaces it at the start
# of the next session in that repository.
#
# The child reads a digest, not the raw transcript: a real session runs to
# several MB of JSONL, most of it tool output and thinking blocks. The digest
# keeps prompts, replies, Bash commands, edited paths and errors — roughly 4%
# of the bytes, which is what makes one cheap Sonnet call enough.
set -uo pipefail

# Recursion guard: the headless run below ends a session of its own, which
# would fire this hook again.
[[ -n "${CLAUDE_LEARNINGS_CHILD:-}" ]] && exit 0

command -v jq >/dev/null 2>&1 || exit 0
command -v claude >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
REASON="$(jq -r '.reason // empty' <<<"$INPUT" 2>/dev/null)"
CWD="$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)"
TRANSCRIPT="$(jq -r '.transcript_path // empty' <<<"$INPUT" 2>/dev/null)"
SESSION="$(jq -r '.session_id // "unknown"' <<<"$INPUT" 2>/dev/null)"

# `resume` is not an ending: the conversation carries on in another process.
[[ "$REASON" == "resume" ]] && exit 0
[[ -f "$TRANSCRIPT" ]] || exit 0

REPO="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"
[[ -n "$REPO" ]] || exit 0

STATE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/logs"
mkdir -p "$STATE/digests" || exit 0

# One proposal per session, even if the hook fires more than once. The marker
# lives here rather than in the repository so a work tree stays clean.
LOCK="$STATE/.learnings-$SESSION.done"
[[ -e "$LOCK" ]] && exit 0

DIGEST="$STATE/digests/$SESSION.txt"
jq -r '
  def clip($n): if (. | length) > $n then (.[0:$n] + " …") else . end;
  select(.message.content? and (.message.content | type == "array"))
  | .message.role as $role
  | .message.content[]
  | if   .type == "text" and $role == "user"      then "USER: "   + (.text | clip(800))
    elif .type == "text" and $role == "assistant" then "CLAUDE: " + (.text | clip(800))
    elif .type == "tool_use" and .name == "Bash"  then "$ "       + (.input.command // "" | clip(300))
    elif .type == "tool_use" and (.name == "Edit" or .name == "Write") then "EDIT " + (.input.file_path // "")
    elif .type == "tool_result" and .is_error == true then
      "ERROR: " + ((.content | if type == "array" then (map(.text? // "") | join(" ")) else tostring end) | clip(300))
    else empty end
' "$TRANSCRIPT" > "$DIGEST" 2>/dev/null

# Too short to have learned anything worth a human's review.
[[ "$(wc -l < "$DIGEST")" -ge 40 ]] || { rm -f "$DIGEST"; exit 0; }

: > "$LOCK"

read -r -d '' PROMPT <<EOF
You are closing out a Claude Code session in this repository. Read $DIGEST —
a condensed transcript of that session, one line per prompt, reply, shell
command, edited path or error — and decide what from it belongs in this
repository's durable agent memory.

Append one dated entry to .claude/claude-md-review.md, newest first, creating
the file with a short header if it does not exist. The entry is a proposal for
the "## DevOps Conventions (agent-maintained)" section of AGENTS.md, worded so
a human can paste the bullets in unedited:

- verified commands, with their exact paths and flags
- conventions and patterns this session confirmed
- gotchas and how they were resolved
- one short imperative rule for anything that should not happen again

Write English, one line per bullet, no paragraphs. Read AGENTS.md and CLAUDE.md
first and skip whatever they already say. Skip preferences and corrections
about how the user likes to work — those belong to auto memory, not here. Merge
into an existing unapplied entry instead of duplicating it, and say so when a
proposal supersedes an older one.

Never edit AGENTS.md, CLAUDE.md, or anything other than
.claude/claude-md-review.md. If the session produced nothing durable, write
nothing at all and say that instead.
EOF

cd "$REPO" || exit 0
CLAUDE_LEARNINGS_CHILD=1 nohup claude -p "$PROMPT" \
  --model sonnet \
  --allowed-tools Read Grep Glob Edit Write \
  >>"$STATE/learnings.log" 2>&1 &
disown 2>/dev/null || true
exit 0
