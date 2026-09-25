#!/usr/bin/env bash
# ~/.claude/scripts/block-mcp-mutations.sh
#
# PreToolUse hook for MCP tools, matched with the regex "mcp__.*".
# block-mutations.sh guards Bash and never sees these calls. tests/guards.sh
# holds the cases this is checked against — run it after any change here.
#
# There is no command string to parse here. Every MCP server has its own input
# schema, so the decision keys on the tool NAME. That is sturdier than the Bash
# side rather than weaker: a name cannot hide behind `bash -c` or a pipe.
#
# Verdicts mirror block-mutations.sh: "ask" for the interactive session, "deny"
# for a subagent, which runs headless and cannot answer a prompt. Who is asking
# is decided the same way there, and the reasoning lives in that script.
#
# Order of the checks, and why:
#   1. A shell-shaped tool (execute_shell_command, run_terminal, ...) is judged
#      even on an allowlisted server: a server trusted for reads is not trusted
#      to hand out a shell that bypasses both guards and the sandbox.
#   2. An allowlisted server passes.
#   3. A write marker anywhere in the tool name asks.
#   4. A read marker passes. Checked after writes, so get_and_delete is a write.
#   5. Anything else asks: an unclassified tool gets no free pass.
#
# Requires jq. Fails CLOSED (exit 2) if jq is missing or the input is not a
# JSON object.
set -uo pipefail

# Servers whose whole surface is read-only, or whose writes are working-tree
# edits the implementer is meant to make (serena). Matched on the server
# segment of the tool name.
READ_ONLY_SERVERS=(
  "context7"
  "awslabs_aws-documentation-mcp-server"
  "headroom"
  "serena"
)

# `execute` alone is left off: execute_query and execute_workflow are writes,
# not shells, and are caught by WRITE_MARKERS with an honest reason.
SHELL_MARKERS='(^|_)(shell|exec|command|commands|terminal|spawn|process|subprocess)(_|$)'
WRITE_MARKERS='(^|_)(write|create|update|delete|remove|merge|complete|queue|run|trigger|deploy|apply|sync|restart|scale|set|put|post|patch|invoke|abandon|publish|push|approve|vote|execute|exec|insert|drop|replace|install|uninstall|terminate|kill|stop|start|reboot|cancel|archive|rename|move|upload|send|assign|grant|revoke|reset|rollback|restore|enable|disable|attach|detach)(_|$)'
READ_MARKERS='(^|_)(list|get|show|search|read|describe|find|view|status|diff|query|fetch|history)(_|$)'

LOG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/logs/mcp-guard.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

INPUT_JSON="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "block-mcp-mutations.sh: jq not found on PATH; failing closed." >&2
  exit 2
fi
if ! printf '%s' "$INPUT_JSON" | jq -e 'type == "object"' >/dev/null 2>&1; then
  echo "block-mcp-mutations.sh: input is not a JSON object; failing closed." >&2
  exit 2
fi

TOOL_NAME="$(printf '%s' "$INPUT_JSON" | jq -r '.tool_name // empty')"
AGENT_TYPE="$(printf '%s' "$INPUT_JSON" | jq -r '.agent_type // empty')"
AGENT_ID="$(printf '%s' "$INPUT_JSON" | jq -r '.agent_id // empty')"

[[ "$TOOL_NAME" == mcp__* ]] || exit 0

# mcp__<server>__<tool>; the tool segment may itself contain underscores.
REST="${TOOL_NAME#mcp__}"
SERVER="${REST%%__*}"
TOOL="$(printf '%s' "${REST#*__}" | tr '[:upper:]-' '[:lower:]_')"

# Same rule as block-mutations.sh: an agent_id means subagent, and so does an
# agent_type outside the interactive list. Real MCP calls from the main session
# carry agent_type=devops (mcp-guard.log, 2026-09-23..25), so the list is needed.
INTERACTIVE_AGENTS=("devops")
IS_HEADLESS=false
if [[ -n "$AGENT_ID" ]]; then
  IS_HEADLESS=true
elif [[ -n "$AGENT_TYPE" ]]; then
  IS_HEADLESS=true
  for i in "${INTERACTIVE_AGENTS[@]}"; do
    [[ "$AGENT_TYPE" == "$i" ]] && IS_HEADLESS=false
  done
fi

# Best effort and silent: a PreToolUse hook's stderr reaches the session.
log() {
  { printf '%s\t%s\tagent_type=%s\tagent_id=%s\t%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TOOL_NAME" "${AGENT_TYPE:-<none>}" \
      "$([[ -n "$AGENT_ID" ]] && echo yes || echo no)" "$1" >>"$LOG"; } 2>/dev/null || true
}

decide() {
  jq -n --arg d "$1" --arg reason "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $reason}}'
  exit 0
}

verdict() {
  if [[ "$IS_HEADLESS" == true ]]; then
    log "deny"
    decide deny "$1 [blocked: a subagent runs headless and cannot confirm]"
  fi
  log "ask"
  decide ask "$1"
}

if [[ "$TOOL" =~ $SHELL_MARKERS ]]; then
  verdict "MCP tool $TOOL_NAME hands out a shell, which bypasses the Bash guard and the sandbox."
fi

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

verdict "MCP server '$SERVER' is not on the read-only list, and $TOOL_NAME does not read like a query."
