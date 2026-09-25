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
# What qualifies and how it is worded lives in docs/learnings.md, which the
# interactive session reads at its own Step 6. The child is pointed at that
# same file rather than carrying a second copy of the policy: one file to
# edit when the rules change, and a proposal written here is interchangeable
# with one written in session.
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

# A digest holds prompts and full shell commands, which is exactly what the
# guard logs avoid recording. Each one is deleted once its child finishes;
# this sweeps up whatever a crashed or killed child left behind.
find "$STATE/digests" -type f -name '*.txt' -mtime +2 -delete 2>/dev/null

POLICY="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/docs/learnings.md"
if [[ ! -f "$POLICY" ]]; then
  echo "learnings-queue: $POLICY missing, run install.sh" >>"$STATE/learnings.log"
  exit 0
fi

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

Then read $POLICY and follow it. It defines what qualifies, where the draft
goes, and how to word it, and it is the same policy the interactive session
follows, so a proposal written here and one written in session are
interchangeable.

What is specific to this run:

- Read AGENTS.md and CLAUDE.md first and skip whatever they already say.
- Skip preferences and corrections about how the user likes to work. Those
  belong to auto memory, not here.
- Nobody can answer a question for you. Where the digest is ambiguous, leave
  the fact out rather than guessing at it.
- Edit nothing but .claude/claude-md-review.md. If the session produced
  nothing durable, write nothing at all and say that instead.
EOF

cd "$REPO" || exit 0
# --agent pins what this child runs as. Without it the child inherits the
# `agent` key from settings.json, so it would boot with the devops prompt —
# an orchestrator told to plan infrastructure and delegate, which is the wrong
# system prompt for summarising a transcript. Defined inline so there is no
# extra agent file to install.
AGENT_JSON='{"learnings-writer":{"description":"Turns one condensed session transcript into a dated proposal for repository agent memory.","prompt":"You read a condensed Claude Code session transcript and write a dated proposal for the repository agent memory of that session. You edit one file and report nothing else. Follow the instructions in the prompt exactly."}}'

# --allowed-tools only pre-approves; it removes nothing. The digest carries
# tool error text from the session, which is untrusted input, and settings.json
# auto-allows sandboxed Bash — so without --disallowed-tools the child could
# run commands a transcript talked it into. It needs to read and edit one file.
(
  # nohup's job: closing the terminal right after the session must not kill
  # the child mid-write. An ignored signal is inherited across exec.
  trap '' HUP
  CLAUDE_LEARNINGS_CHILD=1 claude -p "$PROMPT" \
    --model sonnet \
    --agents "$AGENT_JSON" \
    --agent learnings-writer \
    --allowed-tools Read Grep Glob Edit Write \
    --disallowed-tools Bash WebFetch WebSearch NotebookEdit
  rm -f "$DIGEST"
) >>"$STATE/learnings.log" 2>&1 </dev/null &
disown 2>/dev/null || true
exit 0
