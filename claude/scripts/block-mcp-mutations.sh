#!/usr/bin/env bash
# ~/.claude/scripts/block-mcp-mutations.sh
#
# PreToolUse hook for MCP tools, matched with the regex "mcp__.*".
# block-mutations.sh guards Bash and never sees these calls: its matcher
# is the literal "Bash", and its first check exits on anything else.
#
# There is no command string to parse here. Every MCP server has its own
# input schema, so the decision keys on the tool NAME instead. That is
# sturdier than the Bash side rather than weaker — a name cannot be
# hidden behind `bash -c`, a pipe, or a generated script.
#
# Verdicts mirror block-mutations.sh: "ask" for the interactive session,
# "deny" for a headless subagent that cannot answer a prompt.
#
# UNRESOLVED, deliberately logged rather than guessed: Claude Code's
# documentation does not say whether `agent_type` is set on MCP calls
# the way it is on Bash calls. If it is absent, a headless subagent
# reads as interactive here and gets "ask" where it should get "deny".
# Every decision is logged with the raw agent_type, so a few days of
# real traffic settles it. Revisit once the log shows a subagent call.
#
# Requires jq. Fails CLOSED if jq is missing.
set -uo pipefail

# Servers whose whole surface is read-only, or whose writes are ordinary
# working-tree edits the implementer is supposed to make (serena). These
# pass without a prompt. Matched on the server segment of the tool name.
READ_ONLY_SERVERS=(
  "context7"
  "awslabs_aws-documentation-mcp-server"
  "headroom"
  "serena"
)

# Name fragments meaning the call changes something. Checked against the
# tool segment only, so a server whose name contains "create" does not
# trip every one of its reads.
WRITE_MARKERS='(^|_)(write|create|update|delete|remove|merge|complete|queue|run|trigger|deploy|apply|sync|restart|scale|set|put|post|patch|invoke|abandon|publish|push|approve|vote)(_|$)'

# Name fragments meaning the call only looks. Checked AFTER the write markers,
# so a name carrying both — get_and_delete — is judged on the write. Without
# this, every read from an unclassified server prompts, and a guard that
# prompts on `repo_list_pull_requests` is a guard someone turns off.
READ_MARKERS='(^|_)(list|get|show|search|read|describe|find|view|status|diff|query|fetch|history)(_|$)'

INPUT_JSON="$(cat)"
LOG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/logs/mcp-guard.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

if ! command -v jq >/dev/null 2>&1; then
  echo "block-mcp-mutations.sh: jq not found on PATH; failing closed." >&2
  exit 2
fi

deny() {
  jq -n --arg reason "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

ask() {
  jq -n --arg reason "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}'
  exit 0
}

TOOL_NAME="$(printf '%s' "$INPUT_JSON" | jq -r '.tool_name // empty' 2>/dev/null)"
AGENT_TYPE="$(printf '%s' "$INPUT_JSON" | jq -r '.agent_type // empty' 2>/dev/null)"

[[ "$TOOL_NAME" == mcp__* ]] || exit 0

# mcp__<server>__<tool>; the tool segment may itself contain underscores.
REST="${TOOL_NAME#mcp__}"
SERVER="${REST%%__*}"
TOOL="${REST#*__}"

# The log is best effort and must never speak. A PreToolUse hook's
# stderr is surfaced to the session, so a failed redirect on an
# unwritable log directory would look like the guard itself failing.
log() {
  { printf '%s\t%s\tagent_type=%s\t%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TOOL_NAME" "${AGENT_TYPE:-<none>}" "$1" >>"$LOG"; } 2>/dev/null || true
}

# Same inversion as block-mutations.sh: name the interactive agents, so
# an unknown agent_type fails closed instead of silently losing the deny.
INTERACTIVE_AGENTS=("devops")
IS_HEADLESS=false
[[ -n "$AGENT_TYPE" ]] && IS_HEADLESS=true
for i in "${INTERACTIVE_AGENTS[@]}"; do
  [[ "$AGENT_TYPE" == "$i" ]] && IS_HEADLESS=false
done

verdict() {
  if [[ "$IS_HEADLESS" == true ]]; then
    log "deny"
    deny "$1 [blocked: $AGENT_TYPE runs headless and can't confirm]"
  else
    log "ask"
    ask "$1"
  fi
}

for s in "${READ_ONLY_SERVERS[@]}"; do
  if [[ "$SERVER" == "$s" ]]; then
    log "allow (read-only server)"
    exit 0
  fi
done

if [[ "$TOOL" =~ $WRITE_MARKERS ]]; then
  verdict "MCP tool $TOOL_NAME looks like a write. Confirm it before it runs."
fi

if [[ "$TOOL" =~ $READ_MARKERS ]]; then
  log "allow (read-shaped name)"
  exit 0
fi

# Unknown server, and the name says neither read nor write. A new MCP server
# does not get a free pass just because nobody has classified it yet: read
# what it exposes, then add it to READ_ONLY_SERVERS above.
verdict "MCP server '$SERVER' is not on the read-only list, and $TOOL_NAME does not read like a query."
