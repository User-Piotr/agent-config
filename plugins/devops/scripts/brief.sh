#!/usr/bin/env bash
# plugins/devops/scripts/brief.sh
#
# SessionStart and SubagentStart hook. Injects the DevOps brief into the main
# agent's or the subagent's context through hookSpecificOutput.additionalContext.
# The brief stays short on purpose: it names the skills to load, and the skills
# carry the detail, so their cost is paid only when the work reaches them.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

EVENT="$(jq -r '.hook_event_name // empty' 2>/dev/null)"
case "$EVENT" in
  SessionStart|SubagentStart) ;;
  *) exit 0 ;;
esac

BRIEF='DevOps domain brief (plugin devops). Binding: load the named skill before working in its area.
- Environment: AWS (EKS, Aurora, OpenSearch, IAM) and on-premise Kubernetes, many monorepos, Terraform, Helm, Argo CD, CI/CD pipelines.
- Skills: devops:terraform, devops:helm, devops:kubernetes, devops:aws, devops:pipelines. Before any Terraform change load devops:terraform; likewise for Helm charts, Kubernetes manifests or cluster symptoms, AWS services and IAM, pipeline definitions.
- Live systems: Terraform state and infrastructure, Helm releases, Kubernetes clusters, Argo CD apps, AWS accounts. Reads, plan, template, lint and dry-run or diff are fine; apply, destroy, install, upgrade, rollback, delete, sync and every kubectl write belong to the user. Hand over the exact command.
- Conventions section in AGENTS.md: "## DevOps Conventions (agent-maintained)".
- Shared base charts, Terraform modules and pipeline templates have many consumers: state the blast radius in the plan and check it in review.
- Documentation: mcp__plugin_devops_aws-documentation for AWS service behaviour, limits and APIs; context7 for tool versions.
- Validation to name in a plan: terraform fmt -recursive -check, validate, plan; tflint; Trivy; Semgrep; helm lint and template; kubectl diff --server-side. Recommend a staging smoke test before production.
- Investigators: read-only kubectl get/describe/logs/events, helm get values, terraform state show, Argo CD reads; look for a skill or Grafana/Loki/Prometheus tools before searching from scratch.
- Reviewers: also flag RBAC or IAM widening, and consumers of a changed shared chart or module that the plan does not name.'

jq -n --arg e "$EVENT" --arg c "$BRIEF" \
  '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
exit 0
