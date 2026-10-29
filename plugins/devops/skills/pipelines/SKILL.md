---
name: pipelines
description: CI/CD pipeline work, covering GitHub Actions, Azure DevOps pipelines, shared pipeline templates and security scanning (Semgrep, Trivy). Use before changing a pipeline definition or template, or when a pipeline fails.
---

# Pipelines

The repository's own `AGENTS.md` outranks everything here. Read it first.

- Find the shared pipeline template a repository uses before writing steps inline. A shared template has many consumers: name them and the blast radius in the plan, and pin the version consumers reference.
- GitHub: read workflow definitions and run history with `gh workflow view`, `gh run list`, `gh run view`. `gh workflow run`, `gh run rerun|cancel` and any `gh api` write publish or act: ask first in the main session, and hand them back from subagents.
- Azure DevOps: `az pipelines` and `az repos` reads are fine; writes need the user.
- Security scanning: Semgrep for SAST, Trivy for images, configuration and dependencies. Name the exact command and the severity threshold in the Validation Plan.
- Pin third-party actions and images by digest or full version, and keep tokens in the platform's secret store, never in the definition.
- A failing pipeline: read the failing job's log first, then the template it calls, then recent changes to either.
