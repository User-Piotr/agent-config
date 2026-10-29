#!/usr/bin/env bash
# plugins/morph/scripts/learnings-queue.sh
#
# SessionEnd hook. Queues a learnings proposal for the repository the session
# ran in, then returns immediately.
#
# Why the work happens in a detached child rather than here: SessionEnd hooks
# share a 1.5 s budget (raised to the per-hook timeout, at most 60 s), and
# SessionEnd stdout never reaches the model — by then there is no turn left to
# inject into. So the session that is ending cannot summarise itself. A
# headless `claude -p` does it in the background instead and returns a dated
# entry as text; this script inserts it into .claude/claude-md-review.md.
#
# Why the child returns text instead of editing the file: Claude Code guards
# every path under .claude/ and refuses an edit there in -p mode even when Edit
# is allowed (learnings.log, 2026-10-17: "refused as a sensitive-file edit"), so
# a child that edits writes nothing. Returning text also leaves the child with
# no write tool at all, which matters because the digest it reads carries
# untrusted text from the session. The script decides where the text lands.
#
# Nothing here touches AGENTS.md or CLAUDE.md. The proposal sits in the review
# file until a human applies it; learnings-pending.sh surfaces it at the start
# of the next session in that repository.
#
# What qualifies and how it is worded lives in skills/learnings/SKILL.md, which the
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

# The main repository, not the work tree: --show-toplevel inside a worktree
# names the worktree, so the proposal would land there and vanish with it.
# --git-common-dir points at the shared .git of the main checkout.
COMMON="$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
[[ -n "$COMMON" ]] || exit 0
REPO="$(cd "$COMMON/.." 2>/dev/null && pwd)"
[[ -n "$REPO" && -d "$REPO" ]] || exit 0

STATE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/logs"
mkdir -p "$STATE/digests" || exit 0

# A digest holds prompts and full shell commands, which is exactly what the
# guard logs avoid recording. Each one is deleted once its child finishes;
# this sweeps up whatever a crashed or killed child left behind.
find "$STATE/digests" -type f -name '*.txt' -mtime +2 -delete 2>/dev/null

POLICY="${CLAUDE_PLUGIN_ROOT}/skills/learnings/SKILL.md"
if [[ ! -f "$POLICY" ]]; then
  echo "learnings-queue: $POLICY missing, reinstall the morph plugin" >>"$STATE/learnings.log"
  exit 0
fi

# One proposal per session, even if the hook fires more than once. The marker
# lives here rather than in the repository so a work tree stays clean.
LOCK="$STATE/.learnings-$SESSION.done"
[[ -e "$LOCK" ]] && exit 0

DIGEST="$STATE/digests/$SESSION.txt"
# Typed prompts are stored as a plain string, tool traffic as an array; an
# earlier filter read arrays only and dropped nearly every prompt the user
# wrote. Text the harness injects into the user turn — system reminders, task
# and agent notifications, local command output — is noise, not the user.
jq -r '
  def clip($n): if (. | length) > $n then (.[0:$n] + " …") else . end;
  def injected: test("^\\s*<(system-reminder|task-notification|agent-message|local-command|command-)");
  select(.message.content?)
  | .message.role as $role
  | (.message.content | if type == "string" then [{type: "text", text: .}] else . end)[]
  | if   .type == "text" and $role == "user" and (.text | injected | not) then "USER: " + (.text | clip(800))
    elif .type == "text" and $role == "assistant" then "CLAUDE: " + (.text | clip(800))
    elif .type == "tool_use" and .name == "Bash"  then "$ "       + (.input.command // "" | clip(300))
    elif .type == "tool_use" and (.name == "Edit" or .name == "Write") then "EDIT " + (.input.file_path // "")
    elif .type == "tool_use" and .name == "Read"  then "READ "    + (.input.file_path // "")
    elif .type == "tool_use" and .name == "WebFetch" then "FETCH " + (.input.url // "")
    elif .type == "tool_use" and (.name == "Agent" or .name == "Task") then
      "AGENT " + (.input.subagent_type // "general") + ": " + (.input.description // "")
    elif .type == "tool_result" and .is_error == true then
      "ERROR: " + ((.content | if type == "array" then (map(.text? // "") | join(" ")) else tostring end) | clip(300))
    else empty end
' "$TRANSCRIPT" > "$DIGEST" 2>/dev/null

# Too short to have learned anything worth a human's review. Logged, so that
# an empty learnings.log after a short session reads as a skip, not a failure.
LINES="$(wc -l < "$DIGEST")"
if [[ "$LINES" -lt 40 ]]; then
  rm -f "$DIGEST"
  printf '%s	session=%s	repo=%s	skipped	digest %s lines (< 40)\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SESSION" "$REPO" "$LINES" >>"$STATE/learnings.log"
  exit 0
fi

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
- You cannot edit files. Read .claude/claude-md-review.md if it exists, so
  you do not repeat a pending proposal; where yours supersedes one, say so in
  the entry.
- Reply with exactly one of these, and nothing before or after it:
  - a line \`NOTHING\`, then one sentence on why, when nothing is durable;
  - a line \`PROPOSAL\`, then the complete entry as it should appear in the
    review file, starting with its \`## YYYY-MM-DD — short title\` heading.
    The hook inserts it at the top of the file for you.
EOF

cd "$REPO" || exit 0
# --agent pins what this child runs as. Without it the child inherits the
# `agent` key from settings.json, so it would boot with the morph prompt —
# an orchestrator told to plan and delegate, which is the wrong
# system prompt for summarising a transcript. Defined inline so there is no
# extra agent file to install.
AGENT_JSON='{"learnings-writer":{"description":"Turns one condensed session transcript into a dated proposal for repository agent memory.","prompt":"You read a condensed Claude Code session transcript and return a dated proposal for the repository agent memory of that session, as text. You edit nothing. Follow the instructions in the prompt exactly, including the reply format."}}'
REVIEW="$REPO/.claude/claude-md-review.md"

# --allowed-tools only pre-approves; it removes nothing. The digest carries
# tool error text from the session, which is untrusted input, and settings.json
# auto-allows sandboxed Bash — so without --disallowed-tools the child could
# run commands a transcript talked it into. It only reads; this script writes.
# --no-session-persistence keeps these runs off the `claude --resume` list.
# --strict-mcp-config with no --mcp-config starts no MCP servers, so no
# npx/uvx @latest round-trip at every session end. --bare would skip plugins
# and hooks as well, but it also skips the subscription login ("Not logged
# in", checked 2026-09-25) and would kill every run silently.
# --max-budget-usd is a ceiling, not an estimate: a one-word reply already
# costs over $0.05 in fixed prompt and cache overhead, so a tighter cap would
# cut long sessions off before the proposal is written.
(
  # nohup's job: closing the terminal right after the session must not kill
  # the child mid-write. An ignored signal is inherited across exec.
  trap '' HUP
  OUT="$(CLAUDE_LEARNINGS_CHILD=1 claude -p "$PROMPT" \
    --model sonnet \
    --agents "$AGENT_JSON" \
    --agent learnings-writer \
    --allowed-tools Read Grep Glob \
    --disallowed-tools Edit Write Bash WebFetch WebSearch NotebookEdit Agent \
    --no-session-persistence \
    --strict-mcp-config \
    --max-turns 15 \
    --max-budget-usd 1.00 \
    --output-format json)"
  RESULT="$(printf '%s' "$OUT" | jq -r '.result // empty' 2>/dev/null)"
  FIRST="$(printf '%s\n' "$RESULT" | head -n 1 | tr -d '[:space:]')"
  ENTRY="$(printf '%s\n' "$RESULT" | tail -n +2)"
  # Accept a proposal only in the agreed shape: a dated heading first, and a
  # size no review entry needs. Anything else is logged, never written.
  if [[ "$FIRST" == "PROPOSAL" ]] \
     && printf '%s\n' "$ENTRY" | grep -m1 -v '^[[:space:]]*$' | grep -qE '^## [0-9]{4}-[0-9]{2}-[0-9]{2} ' \
     && [[ "${#ENTRY}" -le 16384 ]]; then
    mkdir -p "$(dirname "$REVIEW")"
    [[ -f "$REVIEW" ]] || printf '# Proposed learnings\n' >"$REVIEW"
    TMP="$(mktemp "$REVIEW.XXXXXX")"
    # Newest first, directly under the file's `#` title (skills/learnings).
    # ENVIRON, not -v: -v would expand backslash escapes inside the entry.
    ENTRY="$ENTRY" awk '
      !done && /^# / { print; print ""; print ENVIRON["ENTRY"]; done = 1; next }
      { print }
      END { if (!done) { print ""; print ENVIRON["ENTRY"] } }' "$REVIEW" >"$TMP" && mv "$TMP" "$REVIEW"
    OUTCOME="proposed"
    NOTE="$(printf '%s\n' "$ENTRY" | grep -m1 '^## ')"
  elif [[ "$FIRST" == NOTHING* ]]; then
    OUTCOME="nothing"
    NOTE="$(printf '%s\n' "$ENTRY" | tr -s '[:space:]' ' ')"
    [[ -n "${NOTE// /}" ]] || NOTE="$(printf '%s\n' "$RESULT" | head -n 1)"
  else
    OUTCOME="unparsed"
    NOTE="$(printf '%s\n' "${RESULT:-$OUT}" | tr -s '[:space:]' ' ' | cut -c1-500)"
  fi
  # One line per run, so cost and outcome can be totalled with awk later.
  printf '%s' "$OUT" | jq -r --arg s "$SESSION" --arg r "$REPO" --arg o "$OUTCOME" --arg n "$NOTE" '
    [ (now | todate), "session=\($s)", "repo=\($r)",
      "cost_usd=\(.total_cost_usd // "?")", "turns=\(.num_turns // "?")",
      (.subtype // "?"), $o, $n ] | join("\t")' \
    2>/dev/null || printf '%s\tsession=%s\trepo=%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SESSION" "$REPO" "$OUTCOME" "$NOTE"
  rm -f "$DIGEST"
) >>"$STATE/learnings.log" 2>&1 </dev/null &
disown 2>/dev/null || true
exit 0
