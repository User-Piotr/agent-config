#!/usr/bin/env bash
# Table-driven test for both PreToolUse guards. Every row is a real command
# shape, most of them bypasses found in review. Run after any change to
# either guard:
#
#   bash claude/tests/guards.sh
#
# Exit status is the number of failing rows.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASH_GUARD="$HERE/../scripts/block-mutations.sh"
MCP_GUARD="$HERE/../scripts/block-mcp-mutations.sh"

# Keep the guards' logs out of the real ~/.claude while testing.
export CLAUDE_CONFIG_DIR="$(mktemp -d)"
trap 'rm -rf "$CLAUDE_CONFIG_DIR"' EXIT

FAIL=0
PASS=0

# who: ""            plain interactive session, no agent fields
#      top:NAME      top-level session started as agent NAME
#      sub:NAME      call made inside subagent NAME
input() {
  local tool="$1" field="$2" value="$3" who="$4"
  jq -cn --arg t "$tool" --arg f "$field" --arg v "$value" --arg w "$who" '
    {tool_name: $t, tool_input: {($f): $v}}
    + (if   ($w | startswith("top:")) then {agent_type: ($w | ltrimstr("top:"))}
       elif ($w | startswith("sub:"))  then {agent_type: ($w | ltrimstr("sub:")), agent_id: "test-agent-id"}
       else {} end)'
}

verdict() {
  local out rc
  out="$(cat | bash "$1" 2>/dev/null)"; rc=$?
  if [[ $rc -eq 2 ]]; then echo deny; return; fi
  if [[ -z "$out" ]]; then echo allow; return; fi
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo allow
}

check() {
  local want="$1" got="$2" label="$3"
  if [[ "$want" == "$got" ]]; then PASS=$((PASS+1))
  else FAIL=$((FAIL+1)); printf 'FAIL  want %-5s got %-5s  %s\n' "$want" "$got" "$label"
  fi
}

b() { check "$1" "$(input Bash command "$3" "$2" | verdict "$BASH_GUARD")" "bash[$2] $(printf '%q' "$3")"; }
m() { check "$1" "$(input "$3" x x "$2" | verdict "$MCP_GUARD")" "mcp[$2] $3"; }

# --- Bash: live mutations must ask -------------------------------------------
b ask ""  $'cd infra\nterraform apply -auto-approve'
b ask ""  "kubectl --context prod apply -f x.yaml"
b ask ""  "kubectl -n prod delete deploy api"
b ask ""  "terraform -chdir=infra apply"
b ask ""  "helm -n prod upgrade rel ./chart"
b ask ""  'for p in a b; do kubectl delete pod $p; done'
b ask ""  "(kubectl delete pod x)"
b ask ""  "sleep 1 & kubectl delete pod x"
b ask ""  "time terraform apply"
b ask ""  "sudo kubectl delete pod x"
b ask ""  "kubectl delete pod x --dry-run=none"
b ask ""  "helm upgrade rel ./chart --dry-run=false"
b ask ""  "tofu apply"
b ask ""  "terragrunt apply"
b ask ""  "helmfile apply"
b ask ""  "kubectl run tmp --image=busybox"
b ask ""  "echo hi && terraform apply"
b ask ""  'echo $(terraform destroy)'
b ask ""  'bash -c "helm upgrade rel ./chart"'
b ask ""  "git -C /repo push origin main"
b ask ""  "az repos pr create --title x"
b ask ""  "sudo -u root kubectl delete pod x"
b ask ""  "env AWS_PROFILE=prod terraform apply"
b ask ""  "/usr/local/bin/terraform apply"
b ask ""  'ssh bastion "kubectl delete pod x"'
b ask ""  "find . -name '*.yaml' -exec kubectl apply -f {} ;"
b ask ""  $'terraform plan\nterraform apply'
b ask ""  "aws-vault exec prod -- terraform apply"
b ask ""  "direnv exec . terraform apply"
b ask ""  "mise exec -- kubectl delete pod x"
b ask ""  "doppler run -- helm upgrade rel ./chart"
b ask ""  "op run -- terraform apply"
b ask ""  $'bash <<EOF\nterraform apply -auto-approve\nEOF'
b ask ""  $'cat <<EOF | sh\nkubectl delete pod x\nEOF'
b ask ""  $'ssh bastion <<\'EOF\'\nkubectl delete pod x\nEOF'
b ask ""  $'sudo bash <<EOF\nhelm uninstall rel\nEOF'

# --- Bash: forge writes must ask ---------------------------------------------
b ask ""  "gh pr create --title x"
b ask ""  "gh api repos/o/r/issues -f title=x"
b ask ""  "gh api --method=POST repos/o/r/issues"
b ask ""  "gh api graphql -f query='mutation { addStar(input:{}) { clientMutationId } }'"
b ask ""  "gh repo archive o/r"
b ask ""  "gh run cancel 123"

# --- Bash: reads must pass ---------------------------------------------------
b allow "" "terraform plan"
b allow "" "tofu plan"
b allow "" "terraform state list"
b allow "" "kubectl --context prod get pods"
b allow "" "kubectl -n prod describe deploy api"
b allow "" "helm template ./chart"
b allow "" "helm upgrade rel ./chart --dry-run"
b allow "" "helm upgrade rel ./chart --dry-run=server"
b allow "" "kubectl apply -f x.yaml --dry-run=client"
b allow "" "git push --dry-run"
b allow "" "timeout 30 terraform plan"
b allow "" "gh api repos/o/r/pulls"
b allow "" "gh api graphql -f query='query { viewer { login } }'"
b allow "" "gh run list"
b allow "" "az repos pr list"
b allow "" "timeout 5 git push --dry-run"
b allow "" "aws-vault exec prod -- terraform plan"
b allow "" "aws-vault exec prod -- aws s3 ls"
b allow "" "git stash push -m wip"
b allow "" "git log --grep push"
b allow "" 'grep -rn "terraform apply" docs/'
b allow "" "echo terraform apply"
b allow "" "terraform plan -destroy"
b allow "" "xargs -I{} kubectl describe pod {}"
b allow "" $'cat > notes.md <<\'EOF\'\nRun terraform apply only after review.\nkubectl delete pod x is how you restart it.\nEOF'
b allow "" "cat <<< 'terraform apply'"
b allow "" $'cat > deploy.sh <<\'EOF\'\nterraform apply -auto-approve\nEOF'
b allow "" $'python3 - <<\'PY\'\nprint("terraform apply")\nPY'
b allow "" $'tee notes.md <<EOF\nkubectl delete pod x restarts it.\nEOF'

# --- Bash: accepted false positives ------------------------------------------
# Known, deliberate: each prompts though nothing live happens. Fixing any of
# them means changing how commands are split or matched, and every such change
# has opened a real bypass somewhere else. Change a row here only on purpose.
b ask ""  'git commit -m "fix; terraform apply docs"'   # ";" splits inside quotes
b ask ""  "kubectl get pod apply"                        # a pod named like a verb
b ask ""  "helm plugin install https://example.com/p"    # "install" read as a release verb

# --- Bash: who is asking -----------------------------------------------------
b ask  "top:devops"                 "git push origin main"
# Fail-closed until the log proves agent_id alone tells a subagent apart:
# a top-level session under an agent name nobody listed is treated as headless.
b deny "top:some-other-agent"       "git push origin main"
b deny "sub:devops-implementer"      $'cd infra\nterraform apply -auto-approve'
b deny "sub:otcf-devops-implementer" "kubectl apply -f x.yaml"
b deny "sub:general-purpose"         "gh pr create --title x"

# --- Bash: bad input fails closed --------------------------------------------
check deny "$(printf 'not json' | verdict "$BASH_GUARD")" "bash invalid JSON"
check deny "$(printf 'not json' | verdict "$MCP_GUARD")" "mcp invalid JSON"

# --- Bash: the log never records a secret ------------------------------------
input Bash command "GITHUB_TOKEN=ghp_secret123 gh pr list" "" | bash "$BASH_GUARD" >/dev/null 2>&1
if grep -rq 'ghp_secret123' "$CLAUDE_CONFIG_DIR/logs" 2>/dev/null; then
  FAIL=$((FAIL+1)); echo "FAIL  secret from a VAR=value prefix reached the log"
else PASS=$((PASS+1)); fi

# --- MCP ---------------------------------------------------------------------
m allow ""  mcp__context7__query-docs
m allow ""  mcp__serena__find_symbol
m allow ""  mcp__serena__replace_content
m allow ""  mcp__ado__repo_list_pull_requests
m allow ""  mcp__ado__repo_get_pull_request
m ask   ""  mcp__ado__repo_pull_request_write
m ask   ""  mcp__x__execute_query
m ask   ""  mcp__x__search_and_replace
m ask   ""  mcp__x__get_and_terminate_instances
m ask   ""  mcp__serena__execute_shell_command
m ask   ""  mcp__unknown__frobnicate
m deny  "sub:devops-implementer" mcp__ado__repo_pull_request_write
m deny  "sub:devops-implementer" mcp__serena__execute_shell_command
m allow "sub:devops-implementer" mcp__serena__replace_content

echo "passed $PASS, failed $FAIL"
exit "$FAIL"
