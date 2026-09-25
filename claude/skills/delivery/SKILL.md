---
name: delivery
description: Branch, commit and pull request conventions. Use before creating a branch, writing a commit message, opening a pull request, or pushing.
---

# Delivery

The repository's own `AGENTS.md` outranks everything here. Read it first. This file holds the part that does not change between repositories.

## Types

One vocabulary for both branches and commit subjects:

`feat` `fix` `docs` `chore` `ci` `refactor` `test` `build` `perf` `revert`

The scope is the thing changed — a module, chart, pipeline, cluster or component — lowercase:

```
feat(terraform): add ALB access logs to the shared module
fix(eks): pin the CNI addon version
docs(wiki): add a runbook for the Aurora failover
chore(gitops): bump workflow-templates to v0.3.9
ci(workflow-templates): run tflint on pull requests
refactor(helm): extract the probe block into _helpers.tpl
```

The same type and scope name the branch: `feat/terraform-alb-access-logs`.

This vocabulary is the team's: apply it even where a repository's own history predates it.

## Branch

- Branch from the branch feature work merges into: the default branch (`git symbolic-ref --short refs/remotes/origin/HEAD`), unless the repository promotes through another. Every commit of yours lands on a branch of your own.
- Some repositories here promote feature → `qa` → `master`, and there `master` lags behind. Their `AGENTS.md` says so. Where it is silent but a `qa` branch is ahead of the default — `git rev-list --count origin/<default>..origin/qa` above zero — ask before branching, and propose the answer as a learning for that repository.
- `<type>/<scope>-<what>`, lowercase, hyphens.
- One branch per plan artifact. Where a plan spans repositories, keep the same branch name in each so the set stays findable — `docs/working-agreements` and `docs/knowledge-graph-pointer` already work this way.

## Commit

- One line, imperative, no trailing period, under 72 characters including the prefix.
- The subject names the change, not the file: `fix(argocd): stop the app self-healing on drift`, not `fix(argocd): update values.yaml`.
- No body, no trailers, no attribution lines, no emoji.
- Commit as you go. A passing dry-run is the moment; the end of a session is not.
- Check what the remote holds before `git commit --amend`. Force-push only when the user asks for it.

## Pull request

- Target the branch you started from. Promotion between long-lived branches — `qa` into `master` — is a release step and stays with the user.
- Title is the branch's intent, in the same style as a commit subject.
- Body is empty or one line. Link the plan artifact when one exists.
- Open it with `gh pr create` on a GitHub remote; on an Azure DevOps remote use the ADO MCP server, or `az repos pr create` when it is unavailable.
- `git push` and opening a pull request need the user's confirmation every time. Name what lands where, then run it.
- Report the checks — `gh pr checks`, or `az repos pr show` on ADO — and hand the merge to the user.
