#!/usr/bin/env bash
# ~/.claude/scripts/block-mutations.sh
#
# PreToolUse hook for the Bash tool (Claude Code), referenced by
# devops.md, devops-implementer.md, and troubleshooter.md.
#
# Verified 2026-09-23: an "ask" verdict reaches the human even when the
# session runs in auto mode, where a request to disable the Bash sandbox
# is answered by a classifier instead. Two different gates; "ask" is the
# one that still costs a person a decision. Do not water it down to
# "allow" on the assumption that nobody is looking.
#
# Two verdicts, chosen by WHO is running the command:
#
#   - devops-implementer / troubleshooter (headless, cannot ask anyone
#     anything): every category below is a hard DENY, no exceptions.
#     They deliver working-tree edits; the interactive session commits.
#   - the interactive `devops` session (a human is actually watching):
#     terraform apply/destroy, helm install/upgrade/uninstall/rollback/
#     delete, kubectl mutations, argocd app mutations, git push, gh
#     write subcommands (including `gh api` with a write method) and
#     `az repos` write subcommands get "ask" instead — Claude Code
#     prompts the user to confirm before running.
#
# `git commit` is deliberately NOT in any category: committing is
# expected of Claude and creates nothing the user cannot undo locally.
# Publishing steps — `git push`, `gh pr create` — are the ones that ask,
# because they are what other people see. Live-environment mutations
# (terraform apply, helm, kubectl, argocd) also ask, but the user
# normally runs those by hand.
#
# Claude Code sets `agent_type` on the hook's JSON input when the call
# happens inside a subagent, and leaves it empty for a plain top-level
# session. A session started with `--agent devops` also carries one, so
# "any agent_type present" would wrongly make the interactive session
# headless — hence a list.
#
# The list names the INTERACTIVE agents, not the headless ones, so an
# unknown agent_type fails closed. An earlier version listed the
# headless ones: a fork that renamed them to otcf-devops-implementer
# and otcf-troubleshooter silently dropped to the "ask" path, with
# nothing in the output or the logs to say it had lost the deny. Add a
# name here only when a new agent genuinely has a human watching it.
INTERACTIVE_AGENTS=("devops")
#
# Dry-run / template / lint / diff / plan forms are still always
# allowed outright (no ask, no deny) — see the DRY_RUN check below.
# terraform apply/destroy has no dry-run form of its own (`terraform
# plan` is the read-only equivalent) so it's never exempted that way.
#
# This is best-effort text matching on the Bash command string, not a
# real shell parser: it splits on &&, ||, ;, |, backticks, and $(...) so
# each sub-command is checked, and anchors each pattern to the start of
# a sub-command (allowing a leading path or VAR=val assignments) to cut
# down on false positives like `echo "don't run terraform apply"`. It
# is not proof against a determined obfuscation attempt — pair it with
# `deny` rules in settings.json and real least-privilege credentials
# (read-only kube context, a GitHub token with no write scopes, a cloud
# role with no apply rights) so a bypass here still can't mutate
# anything for real.
#
# Requires jq. Fails CLOSED (denies, via exit 2) if jq is missing or
# the input can't be read as JSON — a hook that can't verify a command
# should not wave it through, and "ask" is only safe to offer when we
# can actually build the JSON that requests it.

set -uo pipefail

# One line per Bash call, to settle an assumption this script has rested on
# since it was written: that a call made inside a subagent carries agent_type.
# Nothing has ever observed that in real traffic — the two-verdict model is
# built on it, so it is worth a few hundred kilobytes to know. Only the first
# word of the command is recorded: a binary name is not a secret, a full
# command line can be.
LOG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/logs/mutations-guard.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null

INPUT_JSON="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "block-mutations.sh: jq not found on PATH; failing closed." >&2
  exit 2
fi

# Best effort and silent: a PreToolUse hook's stderr reaches the session, so a
# failed redirect on an unwritable log directory would read as the guard itself
# breaking.
log() {
  { printf '%s\t%s\tagent_type=%s\t%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${BIN:-?}" "${AGENT_TYPE:-<none>}" "$1" >>"$LOG"; } 2>/dev/null || true
}

deny() {
  local reason="$1"
  jq -n --arg reason "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

ask() {
  local reason="$1"
  jq -n --arg reason "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}'
  exit 0
}

# Headless subagents always get the hard-deny path; the interactive
# session gets "ask" for the categories below.
verdict() {
  if [[ "$IS_HEADLESS" == true ]]; then
    log "deny"
    deny "$1 [blocked: $AGENT_TYPE runs headless and can't confirm]"
  else
    log "ask"
    ask "$1"
  fi
}

TOOL_NAME="$(printf '%s' "$INPUT_JSON" | jq -r '.tool_name // empty' 2>/dev/null)"
COMMAND="$(printf '%s' "$INPUT_JSON" | jq -r '.tool_input.command // empty' 2>/dev/null)"
AGENT_TYPE="$(printf '%s' "$INPUT_JSON" | jq -r '.agent_type // empty' 2>/dev/null)"

[[ "$TOOL_NAME" == "Bash" ]] || exit 0
[[ -n "$COMMAND" ]] || exit 0

BIN="${COMMAND%%[[:space:]]*}"

IS_HEADLESS=false
[[ -n "$AGENT_TYPE" ]] && IS_HEADLESS=true
for i in "${INTERACTIVE_AGENTS[@]}"; do
  [[ "$AGENT_TYPE" == "$i" ]] && IS_HEADLESS=false
done

# Split on common chaining/substitution operators so each sub-command
# gets checked, not just the first one on the line.
# The replacement is a backslash followed by a real newline, not \n: \n on the
# right-hand side is a GNU extension, and BSD sed on macOS substitutes a
# literal "n" instead. That would collapse `a && terraform apply` into one
# sub-command, and the anchored patterns below would only ever see the first.
#
# `)` splits too, so the tail of a $(...) substitution does not arrive as
# `terraform destroy)` — a trailing paren is neither whitespace nor
# end-of-string, and the verb patterns would miss it. Splitting more is always
# the safe direction: every fragment is re-anchored and re-checked.
SPLIT="$(printf '%s' "$COMMAND" | tr '\n' ' ' | sed -E 's/(&&|\|\||;|\||`|\$\(|\))/\
/g')"

# Allowed prefix before a binary name: optional VAR=val assignments
# and/or a path, e.g. `FOO=bar /usr/local/bin/terraform apply`.
PREFIX='^([[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)*[[:space:]]*([^[:space:]]*/)?'

while IFS= read -r RAW; do
  SUB="$(printf '%s' "$RAW" | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//')"
  [[ -z "$SUB" ]] && continue
  LOWER="$(printf '%s' "$SUB" | tr '[:upper:]' '[:lower:]')"

  DRY_RUN=false
  [[ "$LOWER" =~ --dry-run(=[a-z]+)?([[:space:]]|$) ]] && DRY_RUN=true
  [[ "$LOWER" =~ --server-dry-run([[:space:]]|$) ]] && DRY_RUN=true

  # terraform state rm/mv/push, import, taint and force-unlock rewrite
  # state without touching a provider, so they are never dry-run exempt.
  # state list/show/pull are reads and must not match.
  if [[ "$LOWER" =~ ${PREFIX}terraform[[:space:]]+state[[:space:]]+(rm|mv|push|replace-provider)([[:space:]]|$) ]] \
  || [[ "$LOWER" =~ ${PREFIX}terraform[[:space:]]+(import|taint|untaint|force-unlock)([[:space:]]|$) ]] \
  || [[ "$LOWER" =~ ${PREFIX}terraform[[:space:]]+workspace[[:space:]]+delete([[:space:]]|$) ]]; then
    verdict "terraform state/import/taint rewrites state. 'terraform state list|show|pull' reads it without changing it."
  fi

  # terraform apply/destroy: flagged always, dry-run or not.
  if [[ "$LOWER" =~ ${PREFIX}terraform[[:space:]]+(apply|destroy)([[:space:]]|$) ]]; then
    verdict "terraform apply/destroy is a live-environment mutation. Use 'terraform plan' if you just need to see the diff."
  fi

  if [[ "$DRY_RUN" == false ]]; then
    if [[ "$LOWER" =~ ${PREFIX}helm[[:space:]]+(install|upgrade|uninstall|rollback|delete)([[:space:]]|$) ]]; then
      verdict "helm install/upgrade/uninstall/rollback/delete is a live-environment mutation. Use 'helm template'/'helm lint'/--dry-run if you just need to see the diff."
    fi

    if [[ "$LOWER" =~ ${PREFIX}kubectl[[:space:]]+(apply|delete|patch|scale|replace|edit|drain|cordon|uncordon|create|annotate|label|taint|expose|autoscale)([[:space:]]|$) ]] \
  || [[ "$LOWER" =~ ${PREFIX}kubectl[[:space:]]+rollout[[:space:]]+(restart|undo)([[:space:]]|$) ]] \
  || [[ "$LOWER" =~ ${PREFIX}kubectl[[:space:]]+(exec|debug|attach|cp|set)([[:space:]]|$) ]]; then
      verdict "kubectl mutation detected. Use 'kubectl diff --server-side' or --dry-run=client/server if you just need to see the diff."
    fi

    if [[ "$LOWER" =~ ${PREFIX}argocd[[:space:]]+app[[:space:]]+(sync|delete|rollback|patch|set|create)([[:space:]]|$) ]]; then
      verdict "argocd app mutation detected."
    fi
  fi

  # git push: the first step other people can see, so it asks. A hard
  # deny for the headless subagents, which hand work back as working-tree
  # edits. `git push --dry-run` genuinely doesn't push — exempted
  # outright, not via verdict.
  if [[ "$LOWER" =~ ${PREFIX}git([[:space:]]+(-c[[:space:]]+[^[:space:]]+|-C[[:space:]]+[^[:space:]]+|--git-dir=[^[:space:]]+|--work-tree=[^[:space:]]+|--no-pager|--bare))*[[:space:]]+push([[:space:]]|$) ]] \
  && ! [[ "$LOWER" =~ --dry-run([[:space:]]|$) ]]; then
    verdict "git push writes to the remote."
  fi

  # gh CLI: read-only by default; write subcommands (including `gh
  # api` with a write method) fall into the same loosened category.
  if [[ "$LOWER" =~ ${PREFIX}gh[[:space:]]+(pr[[:space:]]+(create|merge|close|reopen|comment|review|edit)\
|issue[[:space:]]+(create|close|reopen|comment|edit)\
|workflow[[:space:]]+(run|enable|disable)\
|release[[:space:]]+(create|delete|upload|edit)\
|repo[[:space:]]+(create|delete|edit|fork)\
|secret[[:space:]]+(set|delete))([[:space:]]|$) ]]; then
    verdict "gh write subcommand detected."
  fi

  if [[ "$LOWER" =~ ${PREFIX}gh[[:space:]]+api[[:space:]] ]] \
  && [[ "$LOWER" =~ (-x|--method)[[:space:]]*(post|put|patch|delete) ]]; then
    verdict "gh api call uses a write HTTP method."
  fi

  # A wrapper hides a guarded command from every anchored pattern above:
  # the split runs on shell operators, not on quoted arguments, so
  # `bash -c "terraform apply"` matches `bash` and never `terraform`.
  # Rather than parse the quoting, flag the pair — a wrapper form plus a
  # guarded MUTATION (not merely a guarded binary) in the same
  # sub-command, so `timeout 30 terraform plan` stays untouched.
  if [[ "$LOWER" =~ ${PREFIX}(bash|sh|zsh|eval|xargs|env|timeout|nohup|nice|script)([[:space:]]|$) ]] \
  && [[ "$LOWER" =~ (terraform[[:space:]]+(apply|destroy|import|taint|untaint|force-unlock)\
|terraform[[:space:]]+state[[:space:]]+(rm|mv|push)\
|helm[[:space:]]+(install|upgrade|uninstall|rollback|delete)\
|kubectl[[:space:]]+(apply|delete|patch|scale|replace|edit|create|exec|debug|drain|cp|set)\
|argocd[[:space:]]+app[[:space:]]+(sync|delete|rollback|patch|set|create)\
|git[[:space:]]+push\
|gh[[:space:]]+(pr|issue|workflow|release|repo|secret)[[:space:]]+(create|merge|close|delete|run|set|upload|fork)\
|az[[:space:]]+repos) ]]; then
    verdict "a guarded mutation appears inside a wrapper, where the per-command checks cannot reach it. Run it directly so it can be judged on its own."
  fi

  # Azure DevOps repositories are reached with `az repos`, not `gh`.
  # Same publishing category: everything that writes to the remote or
  # to a pull request asks; `az repos ... list/show` stays untouched.
  if [[ "$LOWER" =~ ${PREFIX}az[[:space:]]+repos[[:space:]]+(pr[[:space:]]+(create|update|set-vote)\
|pr[[:space:]]+(reviewer|work-item)[[:space:]]+(add|remove)\
|create|delete|update\
|import[[:space:]]+create\
|policy[[:space:]]+[a-z-]+[[:space:]]+(create|update|delete)\
|ref[[:space:]]+(create|delete))([[:space:]]|$) ]]; then
    verdict "az repos write subcommand detected."
  fi

done <<< "$SPLIT"

log "allow"
exit 0
