---
name: helm
description: Helm chart work. Use before changing a chart, values file or shared base chart, or when rendering, linting or diffing a release.
---

# Helm

The repository's own `AGENTS.md` outranks everything here. Read it first.

## Shape of the work

- Find the existing chart the change follows (similar chart, `_helpers.tpl`, values layout) before writing a new one.
- A shared base chart has many consumers. Name them and the blast radius in the plan, and check consumers with `graphify affected` when the repository has a graph.
- Keep changes backward-compatible: new values get defaults that preserve the current rendering.
- No secrets in `values.yaml`. Reference a secrets manager or sealed secrets.

## Validate, read-only

```bash
helm lint <chart> -f <values>
helm template <release> <chart> -f <values>      # compare against the current rendering
helm template ... | kubectl diff --server-side -f -   # when a cluster is reachable
```

`helm install|upgrade --dry-run` is also read-only.

## Live mutation belongs to the user

`helm install`, `upgrade`, `uninstall`, `rollback`, `delete` (without `--dry-run`) and `helmfile apply|sync|destroy|delete` change a release. Hand the user the exact command with the release, namespace and values files. `helm get values|manifest`, `list`, `status`, `history`, `template`, `lint` and `helmfile diff` are reads.
