#!/usr/bin/env bash
# ~/.claude/scripts/block-mutations.sh
#
# PreToolUse hook for the Bash tool (Claude Code), referenced by
# devops.md, devops-implementer.md, and troubleshooter.md.
#
# Two verdicts, chosen by WHO is running the command:
#
#   - devops-implementer / troubleshooter (headless, cannot ask anyone
#     anything): every category below is a hard DENY, no exceptions.
#     They deliver working-tree edits; the interactive session commits.
#   - the interactive `devops` session (a human is actually watching):
#     terraform apply/destroy, helm install/upgrade/uninstall/rollback/
#     delete, kubectl mutations, argocd app mutations, git push, and gh
#     write subcommands (including `gh api` with a write method) get
#     "ask" instead — Claude Code prompts the user to confirm before
#     running.
#
# `git commit` is deliberately NOT in any category: committing is
# expected of Claude and creates nothing the user cannot undo locally.
# Publishing steps — `git push`, `gh pr create` — are the ones that ask,
# because they are what other people see. Live-environment mutations
# (terraform apply, helm, kubectl, argocd) also ask, but the user
# normally runs those by hand.
#
# Claude Code sets `agent_type` on the hook's JSON input when the call
# happens inside a subagent. We key off the specific names below rather
# than "any agent_type present", because a top-level session invoked
# with `--agent devops` would also carry agent_type — and that should
# still count as the interactive case. Add a name here if you introduce
# another headless subagent later.
HEADLESS_AGENTS=("devops-implementer" "troubleshooter")
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

INPUT_JSON="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "block-mutations.sh: jq not found on PATH; failing closed." >&2
  exit 2
fi

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
    deny "$1 [blocked: $AGENT_TYPE runs headless and can't confirm]"
  else
    ask "$1"
  fi
}

TOOL_NAME="$(printf '%s' "$INPUT_JSON" | jq -r '.tool_name // empty' 2>/dev/null)"
COMMAND="$(printf '%s' "$INPUT_JSON" | jq -r '.tool_input.command // empty' 2>/dev/null)"
AGENT_TYPE="$(printf '%s' "$INPUT_JSON" | jq -r '.agent_type // empty' 2>/dev/null)"

[[ "$TOOL_NAME" == "Bash" ]] || exit 0
[[ -n "$COMMAND" ]] || exit 0

IS_HEADLESS=false
for h in "${HEADLESS_AGENTS[@]}"; do
  [[ "$AGENT_TYPE" == "$h" ]] && IS_HEADLESS=true
done

# Split on common chaining/substitution operators so each sub-command
# gets checked, not just the first one on the line.
SPLIT="$(printf '%s' "$COMMAND" | tr '\n' ' ' | sed -E 's/(&&|\|\||;|\||`|\$\()/\n/g')"

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

  # terraform apply/destroy: flagged always, dry-run or not.
  if [[ "$LOWER" =~ ${PREFIX}terraform[[:space:]]+(apply|destroy)([[:space:]]|$) ]]; then
    verdict "terraform apply/destroy is a live-environment mutation. Use 'terraform plan' if you just need to see the diff."
  fi

  if [[ "$DRY_RUN" == false ]]; then
    if [[ "$LOWER" =~ ${PREFIX}helm[[:space:]]+(install|upgrade|uninstall|rollback|delete)([[:space:]]|$) ]]; then
      verdict "helm install/upgrade/uninstall/rollback/delete is a live-environment mutation. Use 'helm template'/'helm lint'/--dry-run if you just need to see the diff."
    fi

    if [[ "$LOWER" =~ ${PREFIX}kubectl[[:space:]]+(apply|delete|patch|scale|replace|edit|drain|cordon|uncordon|create|annotate|label)([[:space:]]|$) ]] \
    || [[ "$LOWER" =~ ${PREFIX}kubectl[[:space:]]+rollout[[:space:]]+(restart|undo)([[:space:]]|$) ]]; then
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
  if [[ "$LOWER" =~ ${PREFIX}git[[:space:]]+push([[:space:]]|$) ]] \
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

done <<< "$SPLIT"

exit 0
