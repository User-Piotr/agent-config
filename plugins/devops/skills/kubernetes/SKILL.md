---
name: kubernetes
description: Kubernetes and Argo CD work on EKS and on-premise clusters. Use before changing manifests, or when investigating failing pods, deploys, sync problems, events or RBAC.
---

# Kubernetes and Argo CD

The repository's own `AGENTS.md` outranks everything here. Read it first.

## Shape of the work

- Know which cluster and namespace a workload lives in before reading or changing anything; EKS and on-premise clusters differ in ingress, storage classes, IAM integration and node management. Record the mapping you establish for the next run.
- Follow existing manifests and GitOps layout. Argo CD owns what it syncs: a manual change to a synced resource is reverted, so change the source.
- Watch for RBAC widening, network exposure and missing resource limits in every manifest change.

## Read verbs

Safe without asking: `kubectl get`, `describe`, `logs`, `events`, `top`, `auth can-i`, `kubectl diff --server-side`, any verb with `--dry-run=client|server`, and Argo CD reads (`argocd app get|list|diff|history|manifests`).

## Live mutation belongs to the user

`kubectl apply|delete|patch|scale|replace|edit|drain|cordon|uncordon|create|annotate|label|taint|expose|autoscale|run|exec|debug|attach|cp|set` and `rollout restart|undo|pause|resume` change a cluster, and so do `argocd app sync|delete|rollback|patch|set|create|terminate-op`. Without a dry-run flag, never run them. Hand the user the exact command with context and namespace.

## Investigating

Form two or three hypotheses, then gather only the evidence that tells them apart: events first, then the failing pod's describe and logs (previous container too), then the controller's view. Do not dump whole `describe` output and hope.
