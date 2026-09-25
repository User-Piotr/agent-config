#!/usr/bin/env bash
# ~/.claude/scripts/block-mutations.sh
#
# PreToolUse hook for the Bash tool. Guards live-environment mutations and
# forge writes. Referenced by devops.md, devops-implementer.md and
# troubleshooter.md; tests/guards.sh holds the cases it is checked against —
# run it after any change here.
#
# Verified 2026-09-23: an "ask" verdict reaches the human even when the
# session runs in auto mode, where a request to disable the Bash sandbox is
# answered by a classifier instead. Two different gates; "ask" is the one
# that still costs a person a decision. Do not water it down to "allow" on
# the assumption that nobody is looking.
#
# Two verdicts, chosen by WHO is running the command:
#   - a subagent, which runs headless and cannot answer a prompt: DENY.
#   - the interactive session: "ask", so Claude Code prompts first.
# `git commit` is deliberately unguarded: committing is expected and undoable
# locally. Publishing and live mutations are what other people see.
#
# This is the backstop, not the only layer. `permissions.ask` in
# settings.json covers the same categories with Claude Code's own parser.
# This script exists for what that parser does not see — `sudo`,
# `env VAR=x`, `bash -c "..."`, absolute paths — and for the hard deny a
# subagent needs, which a permission rule cannot express.
#
# How a command is read. Text matching, not a shell parser:
#   1. Heredoc bodies are dropped, so a document that merely mentions
#      `terraform apply` does not trip the guard.
#   2. The rest splits on newlines, && || ; | & ( ) ` and $(, so every
#      sub-command is judged, including loop bodies and subshells.
#   3. Each piece loses quotes, leading shell keywords (do, then, if, !),
#      VAR=value assignments and a path in front of the binary.
#   4. Verbs are looked for anywhere after the binary, so global flags in
#      front of the verb (`kubectl --context prod apply`,
#      `terraform -chdir=x apply`, `helm -n prod upgrade`) are still seen.
#   5. A wrapper (sudo, env, timeout, bash -c, xargs, ssh, find -exec, ...)
#      is searched for a guarded binary and judged from there.
#
# Blind by construction to what a script file or a Makefile does
# (`./deploy.sh`, `make apply`) and to deliberate obfuscation. Keep
# least-privilege credentials behind it wherever you can.
#
# Requires jq. Fails CLOSED (exit 2) if jq is missing or the input is not a
# JSON object: a guard that cannot read the call must not wave it through.
set -uo pipefail

# One line per call: time, judged binary, agent fields, verdict. Only the
# binary is recorded — never the command line, which can carry a secret.
LOG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/logs/mutations-guard.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

INPUT_JSON="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "block-mutations.sh: jq not found on PATH; failing closed." >&2
  exit 2
fi
if ! printf '%s' "$INPUT_JSON" | jq -e 'type == "object"' >/dev/null 2>&1; then
  echo "block-mutations.sh: input is not a JSON object; failing closed." >&2
  exit 2
fi

TOOL_NAME="$(printf '%s' "$INPUT_JSON" | jq -r '.tool_name // empty')"
COMMAND="$(printf '%s' "$INPUT_JSON" | jq -r '.tool_input.command // empty')"
AGENT_TYPE="$(printf '%s' "$INPUT_JSON" | jq -r '.agent_type // empty')"
AGENT_ID="$(printf '%s' "$INPUT_JSON" | jq -r '.agent_id // empty')"

[[ "$TOOL_NAME" == "Bash" ]] || exit 0
[[ -n "$COMMAND" ]] || exit 0

# --- who is asking ------------------------------------------------------------
# Observed in real traffic (mutations-guard.log, 2026-09-23..25): agent_type is
# set both inside subagents AND in a top-level session started as an agent —
# 62 calls from this very session carried agent_type=devops. So agent_type
# alone cannot tell a human from a subagent.
#
# agent_id is documented as present only inside a subagent, which would make
# it the clean signal. Until the log shows that holds, both rules apply: an
# agent_id means subagent, and so does any agent_type outside the list of
# agents a human drives. The list names the INTERACTIVE agents, so a renamed
# fork fails closed — an earlier version listed the headless ones, and a fork
# calling them otcf-* silently lost the deny.
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

# --- verdicts -----------------------------------------------------------------
BIN="?"

# Best effort and silent: a PreToolUse hook's stderr reaches the session, so a
# failed write to an unwritable log directory would read as the guard failing.
log() {
  { printf '%s\t%s\tagent_type=%s\tagent_id=%s\t%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BIN" "${AGENT_TYPE:-<none>}" \
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

# --- reading the command ------------------------------------------------------
# Heredoc bodies: keep the line that opens one, drop the lines up to its
# terminator — a body is data, and a document that mentions `terraform apply`
# is not a command. Except when the opening line feeds the heredoc to a shell
# (`bash <<EOF`, `cat <<EOF | sh`, `ssh host <<EOF`): then the body runs, and
# is judged like any other command. The shell has to stand as its own word, so
# `cat > deploy.sh <<EOF` still writes a script without being read as one.
# `<<<` is a here-string, not a heredoc, and is left alone.
BODY="$(printf '%s\n' "$COMMAND" | awk -v q="'" '
  skip { t = $0; gsub(/^[ \t]+|[ \t]+$/, "", t); if (t == term) skip = 0; next }
  { print }
  {
    if (match($0, "(^|[^<])<<-?[ \t]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*")) {
      s = substr($0, RSTART, RLENGTH)
      sub(/^[^<]*<<-?[ \t]*/, "", s)
      gsub("[\"" q "]", "", s)
      term = s
      skip = (tolower($0) ~ "(^|[ |;&(/])(bash|sh|zsh|dash|ksh|ssh|su|eval)( |$)") ? 0 : 1
    }
  }')"

# The replacement is a backslash followed by a real newline, not \n: \n on the
# right-hand side is a GNU extension, and BSD sed on macOS writes a literal
# "n" instead, which would collapse every chain into one piece.
SPLIT="$(printf '%s\n' "$BODY" | sed -E 's/(&&|\|\||;|\||&|`|\$\(|\(|\))/\
/g')"

RE_KEYWORD='^(do|then|else|elif|if|while|until|!|\{|\}) +(.*)$'
RE_ASSIGN='^[a-z_][a-z0-9_]*=[^ ]* +(.*)$'
RE_PATH='^[^ ]*/([^/ ]+)( .*)?$'

normalize() {
  local s prev=""
  s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')"
  s="${s//\"/}"; s="${s//\'/}"
  s="${s# }"; s="${s% }"
  while [[ "$s" != "$prev" ]]; do
    prev="$s"
    if   [[ "$s" =~ $RE_KEYWORD ]]; then s="${BASH_REMATCH[2]}"
    elif [[ "$s" =~ $RE_ASSIGN  ]]; then s="${BASH_REMATCH[1]}"
    fi
  done
  [[ "$s" =~ $RE_PATH ]] && s="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  printf '%s' "$s"
}

is_guarded() {
  case "$1" in terraform|tofu|terragrunt|helm|helmfile|kubectl|argocd|git|gh|az) return 0 ;; esac
  return 1
}

is_wrapper() {
  case "$1" in
    sudo|doas|env|nice|ionice|nohup|time|timeout|stdbuf|command|exec|builtin|noglob|\
    xargs|bash|sh|zsh|dash|eval|ssh|watch|find|parallel|su|script|flock|chroot|caffeinate|\
    aws-vault|direnv|mise|asdf|devbox|doppler|op|dotenv) return 0 ;;
  esac
  return 1
}

# S holds one normalized sub-command whose first word is a guarded binary.
S=""
has()   { local re=" ($1) ";  [[ " $S " =~ $re ]]; }
first() { local re="^[^ ]+ ($1)( |$)"; [[ "$S" =~ $re ]]; }

DRY_RE='--dry-run|--dry-run=(client|server|true)|--server-dry-run'

gh_api_writes() {
  local a=" $S " re
  re=' (-x *|--method[= ])(post|put|patch|delete) ';           [[ "$a" =~ $re ]] && return 0
  re=' (-x *|--method[= ])get ';                               [[ "$a" =~ $re ]] && return 1
  re=' graphql ';                  if [[ "$a" =~ $re ]]; then re='[^a-z]mutation[^a-z]'; [[ "$a" =~ $re ]]; return; fi
  re=' (-f|--field|--raw-field|--input)[ =]';                  [[ "$a" =~ $re ]]
}

git_subcommand() {
  local rest="${S#git}" re='^ (-c [^ ]+|--git-dir=[^ ]+|--work-tree=[^ ]+|--namespace=[^ ]+|--no-pager|--bare|-p|--paginate|--no-replace-objects)(.*)$'
  while [[ "$rest" =~ $re ]]; do rest="${BASH_REMATCH[2]}"; done
  rest="${rest# }"
  printf '%s' "${rest%% *}"
}

judge() {
  BIN="${S%% *}"
  case "$BIN" in
    terraform|tofu|terragrunt)
      if has 'apply|destroy|import|taint|untaint|force-unlock' \
      || has 'state (rm|mv|push|replace-provider)' || has 'workspace delete'; then
        verdict "$BIN changes infrastructure or state. 'plan', 'state list' and 'state show' read without changing anything."
      fi ;;
    helm)
      if ! has "$DRY_RE" && has 'install|upgrade|uninstall|rollback|delete'; then
        verdict "helm release change. Use 'helm template', 'helm lint' or --dry-run to see the diff."
      fi ;;
    helmfile)
      if has 'apply|sync|destroy|delete'; then
        verdict "helmfile release change. 'helmfile diff' or 'template' reads without changing anything."
      fi ;;
    kubectl)
      if ! has "$DRY_RE" \
      && { has 'apply|delete|patch|scale|replace|edit|drain|cordon|uncordon|create|annotate|label|taint|expose|autoscale|run|exec|debug|attach|cp|set' \
           || has 'rollout (restart|undo|pause|resume)'; }; then
        verdict "kubectl mutation. Use 'kubectl diff --server-side' or --dry-run=client|server to see the diff."
      fi ;;
    argocd)
      if has 'app (sync|delete|rollback|patch|set|create|terminate-op)'; then
        verdict "argocd app mutation."
      fi ;;
    git)
      if [[ "$(git_subcommand)" == push ]] && ! has '--dry-run|-n'; then
        verdict "git push writes to the remote."
      fi ;;
    gh)
      if has 'pr (create|merge|close|reopen|comment|review|edit|ready)' \
      || has 'issue (create|close|reopen|comment|edit|delete|transfer|lock|unlock|pin)' \
      || has 'workflow (run|enable|disable)' || has 'run (cancel|rerun|delete)' \
      || has 'release (create|delete|upload|edit)' \
      || has 'repo (create|delete|edit|fork|archive|unarchive|rename|sync)' \
      || has 'secret (set|delete|remove)' || has 'variable (set|delete)' \
      || has 'label (create|edit|delete|clone)' || has 'cache delete'; then
        verdict "gh write subcommand."
      fi
      if first api && gh_api_writes; then
        verdict "gh api call that writes: an explicit write method, a GraphQL mutation, or fields that make it POST by default."
      fi ;;
    az)
      if first repos && { has 'pr (create|update|set-vote)' || has 'pr (reviewer|work-item) (add|remove)' \
         || has 'repos (create|delete|update)' || has 'import create' || has 'ref (create|delete)' \
         || { has 'policy' && has 'create|update|delete'; }; }; then
        verdict "az repos write subcommand."
      fi ;;
  esac
}

# A wrapper hides the binary it runs. Find the first guarded binary among its
# arguments and judge from there: `timeout 5 git push --dry-run` is a dry run,
# `sudo -u root kubectl delete pod x` is not.
judge_wrapped() {
  local -a toks
  local k t
  read -ra toks <<< "$1"
  for ((k = 1; k < ${#toks[@]}; k++)); do
    t="${toks[k]##*/}"
    if is_guarded "$t"; then
      S="$t ${toks[*]:k+1}"
      S="${S% }"
      judge
      return
    fi
  done
}

FIRST=""
while IFS= read -r RAW; do
  SEG="$(normalize "$RAW")"
  [[ -z "$SEG" ]] && continue
  [[ -z "$FIRST" ]] && FIRST="${SEG%% *}"
  HEAD="${SEG%% *}"
  if is_guarded "$HEAD"; then
    S="$SEG"; judge
  elif is_wrapper "$HEAD"; then
    judge_wrapped "$SEG"
  fi
done <<< "$SPLIT"

BIN="${FIRST:-?}"
log "allow"
exit 0
