---
name: aws
description: AWS service work, covering EKS, Aurora, OpenSearch, IAM and cost. Use when a change or problem depends on AWS service behaviour, limits, quotas or permissions.
---

# AWS

The repository's own `AGENTS.md` outranks everything here. Read it first.

- Look up service behaviour, quotas and API shapes with `mcp__plugin_devops_aws-documentation` (`search_documentation`, `read_documentation`, `read_sections`, `search_table` for quotas). Do not answer version- or limit-specific questions from memory.
- IAM: least privilege. Flag any widened policy, wildcard action or resource, and trust-policy change. For pods, prefer the cluster's workload-identity mechanism (IRSA or Pod Identity) already in use over static keys.
- EKS: addon and control-plane versions have upgrade order and skew rules; check the documentation for the exact versions involved.
- Aurora and OpenSearch: changes to parameter groups, instance classes, engine versions or snapshots can restart or replace a cluster. Say so in the plan.
- Cost: note changes that scale spend (instance classes, NAT gateways, log retention, cross-AZ traffic).
- AWS CLI: reads (`describe-*`, `list-*`, `get-*`) are fine. Anything that creates, modifies or deletes is a live mutation: hand the user the exact command.
