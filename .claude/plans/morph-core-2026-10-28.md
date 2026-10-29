# Split devops-core into the generic `morph` plugin and the `devops` domain plugin

## Summary

Turn the setup into a core that any team can use and domain plugins that add
knowledge. `morph` ships a domain-free agent team — `morph:morph` (main, the
default agent), `morph:implementer`, `morph:reviewer`, `morph:investigator` —
with the delivery and learnings skills, the learnings loop and context7.
`devops` depends on `morph` and ships the DevOps knowledge as skills, the
aws-documentation server, and two hooks that brief the agents at start. Every
domain is its own plugin beside the core — `devops` now, `qa` later (out of
scope here). Domain plugins are installed but off by default; the user switches
one on in `/plugin`, globally, and it then applies in every repository.

## Verified (spike, 2026-10-28, Claude Code 2.1.289)

- A plugin's `SessionStart` hook returning `hookSpecificOutput.additionalContext`
  reaches the main agent; a `SubagentStart` hook does the same for every
  subagent. Both were quoted back verbatim by `devops-core:devops` and
  `devops-core:troubleshooter`.
- Given only that brief ("before any Terraform change load `<plugin>:terraform`"),
  a subagent asked to write a `.tf` file loaded the skill on its own and followed
  it (ran `terraform plan`). The prompt asked it to list loaded skills at the
  end, which may have primed it; the before/after test below runs without that.
- Earlier, for the plugin move: plugin agents reach hooks as `<plugin>:<name>`;
  plugin MCP tools are `mcp__plugin_<plugin>_<server>__<tool>`; `memory: local`
  uses `.claude/agent-memory-local/<plugin>-<name>/`; `disallowedTools` patterns
  are honoured; plugin `SessionEnd` hooks fire.

## Naming

| Today | After |
|---|---|
| plugin `devops-core` | plugins `morph` and `devops` |
| `devops-core:devops` | `morph:morph` (default agent) |
| `devops-core:devops-implementer` | `morph:implementer` |
| `devops-core:devops-reviewer` | `morph:reviewer` |
| `devops-core:troubleshooter` | `morph:investigator` |
| `devops-core:delivery`, `devops-core:learnings` | `morph:delivery`, `morph:learnings` |
| `mcp__plugin_devops-core_context7` | `mcp__plugin_morph_context7` |
| `mcp__plugin_devops-core_aws-documentation` | `mcp__plugin_devops_aws-documentation` |
| memory `devops-core-devops-implementer/`, `devops-core-troubleshooter/` | `morph-implementer/`, `morph-investigator/` |

## What moves where

The four prompts keep the way of working and lose the domain. As a rule: a
sentence that would be wrong for a QA or backend repository goes to a `devops`
skill; a sentence that is true anywhere stays in `morph`.

Stays in `morph` (generic):
- Workflow: discover, plan artifact in `.claude/plans/`, approval, delegation by
  artifact path and scope note, review, independent review for shared changes,
  hand-back, learnings. Delegation sizing, cold-start triage, milestone output.
- Rules: English artifacts, no hardcoded secrets, read repo instructions first,
  ask don't assume, delivery via `morph:delivery`.
- Safety, generalised: "never change a live system; hand the user the exact
  command" and "publishing (push, PR) only after the prompt" — what counts as a
  live system is defined by the domain plugin's brief and skills.
- New rule: domain briefs injected at session or subagent start are binding;
  load every skill a brief names before working in that domain.
- New rule: inside the Bash sandbox, `git status` lists dotfiles and `.claude/*`
  paths as untracked — bubblewrap mount points, not files; never commit or
  delete them on that evidence.
- Memory sections; the agent-maintained section of `AGENTS.md` is any
  `## … (agent-maintained)` heading already present, else
  `## Conventions (agent-maintained)` (existing `## DevOps Conventions
  (agent-maintained)` sections keep their name).

Goes to `devops` skills (domain):
- `devops:terraform` — modules and layers, `terraform fmt -recursive -check`,
  `validate`, `plan`, tflint/Trivy, what is a live mutation (`apply`, `destroy`,
  `import`, `state` writes), provider and module conventions.
- `devops:helm` — `helm template`, `helm lint`, `--dry-run`, chart conventions,
  shared base charts and their blast radius.
- `devops:kubernetes` — `kubectl diff --server-side`, read vs write verbs, EKS
  and on-prem specifics, Argo CD (`argocd app` writes, sync options).
- `devops:aws` — AWS docs server usage, IAM/Pod Identity notes, cost-relevant
  checks, Aurora/OpenSearch troubleshooting entry points.
- `devops:pipelines` — CI/CD templates, shared pipeline blast radius, SAST
  (Semgrep, Trivy) as the validation plan's last step.

The exact split of today's text is part of step 3; nothing domain-specific is
dropped, only moved.

## Steps

0. **Verify before building** (a short spike, results recorded here):
   - a marketplace entry with `"defaultEnabled": false` leaves the plugin
     disabled after `claude plugin install`;
   - `claude plugin enable` / `disable` at user scope, on a `settings.json`
     already in the CLI's own format, changes only the `enabledPlugins` line
     (the CLI otherwise reorders keys and turns `"opus"` into `"opus[1m]"`);
   - that format is stable: writing it twice yields the same bytes.
   If the second point fails, the README documents the reformat instead.

   **Result (2026-10-29, isolated `CLAUDE_CONFIG_DIR`, local marketplace):**
   `install` of a `defaultEnabled: false` plugin leaves it disabled and writes
   `"<plugin>@<marketplace>": false` into `enabledPlugins`; on a file already in
   the CLI's format, `install`, `enable` and `disable` each change exactly one
   line; the format is stable across writes, with `"model": "opus[1m]"`.
   Consequence for step 5: commit `settings.json` in that format with
   `"devops@agent-config": false` already present, so the installer's
   `install devops` is byte-neutral and `/plugin enable` is a one-line diff.
   Produce the file by letting the CLI write it in an isolated
   `CLAUDE_CONFIG_DIR`, not by hand.

1. **Rename and restructure `morph`.** `git mv plugins/devops-core plugins/morph`.
   `plugin.json` name `morph`, only `context7` in `mcpServers` (keep the
   `userConfig` key). Agent files and `name:` fields: `morph.md` (`morph`),
   `implementer.md`, `reviewer.md`, `investigator.md`. `settings.json`
   `{"agent": "morph"}`. Marketplace lists `morph` and `devops`, the latter with
   `"defaultEnabled": false`.

2. **Generic prompts.** Rewrite the four agents per "What moves where": every
   cross-reference uses `morph:*`, MCP names use `mcp__plugin_morph_context7`,
   memory paths use `morph-<name>/`, `investigator` keeps `disallowedTools:
   NotebookEdit, Agent, mcp__serena__*`, `implementer` keeps
   `NotebookEdit, Agent`, `reviewer` keeps its allowlist. The learnings skill
   and `learnings-queue.sh` prompt name the agent-maintained section
   generically. Output headings stay.

3. **`devops` plugin.** `plugins/devops/.claude-plugin/plugin.json` with
   `dependencies: ["morph"]` and the `aws-documentation` server.
   `skills/{terraform,helm,kubernetes,aws,pipelines}/SKILL.md` built from the
   text step 2 removed, each with a `description` that names the trigger
   ("Use before changing or validating Terraform …"). `hooks/hooks.json` with
   `SessionStart` and `SubagentStart` both running `scripts/brief.sh`, which
   prints one `additionalContext` (event name taken from the hook input): the
   domain in two lines, which skill to load for which kind of change, and the
   list of live-mutation commands that belong to the user.

4. **Guards.** `INTERACTIVE_AGENTS=("devops" "devops-core:devops" "morph:morph")`
   — the old names stay until every machine has migrated. `READ_ONLY_SERVERS`
   gains `plugin_morph_context7` and `plugin_devops_aws-documentation`; the
   `devops-core` entries stay for the same reason. New guard rows:
   `top:morph:morph` asks, `sub:morph:investigator` and `sub:morph:implementer`
   are denied, `top:morph:anything-else` is denied, both new servers allow,
   look-alikes (`plugin_other_context7`, `plugin_morph_context7_x`) are not trusted.

5. **Settings.** `"agent": "morph:morph"`; `enabledPlugins` has
   `morph@agent-config: true` and `devops@agent-config: false` (off until
   switched on);
   `devops-core@agent-config` removed. Commit the file in the CLI's own format
   (step 0), with `"model": "opus[1m]"`, so a later `/plugin enable` shows as a
   one-line diff.

6. **Installer.** Install `morph` and `devops` (same save/restore of
   `settings.json`; `devops` stays off), print how to switch a domain plugin on,
   configure the context7 key on `morph`, uninstall `devops-core@agent-config`
   when present, and print the memory-directory rename for repositories that
   have `devops-core-*` directories (do not move them automatically: they live
   in other repositories' working trees).

7. **Docs and CI.** README: the core and the domain plugins, which are off
   until switched on in `/plugin` (and that the switch lands in the tracked
   `settings.json` as one line — commit it or not); "Your own plugin"
   rewritten around the brief hooks (the Grafana example gains a `brief.sh`);
   migration from `devops-core` (uninstall, memory renames). CI validates both
   plugins.

Step 0 first, by hand. Then two delegations: steps 1, 2, 4 (the rename lands
with the guard change), then 3, 5, 6, 7.

## Risks & Mitigations

- **Domain knowledge lost in the move.** Step 3 is built from what step 2
  removed, diffed side by side in review; the before/after behaviour test below
  catches a brief that is too weak.
- **Main session hard-denied after the rename.** Step 4 lands with step 1.
- **Agent skips the domain skill.** The brief is injected, not discovered;
  the before/after test runs without any hint in the prompt.
- **`devops` off after migration** on a machine that used `devops-core`: the
  installer says so and prints `/plugin enable devops@agent-config`; on this
  machine it is switched on as part of the rollout.
- **Half-migrated machines** (`devops-core` still enabled next to `morph`):
  settings.json drops it on pull; the installer uninstalls it; README has the
  manual commands.
- **Two prompts' worth of context for the main agent** (morph prompt + brief +
  loaded skills). Briefs stay under ~15 lines; skills load on demand.
- **Blast radius**: every team member's `~/.claude`.
  One machine first; rollback is the previous `main` and `./install.sh`.

## References

- Plan and spike notes: `.claude/plans/plugin-devops-core-2026-10-21.md`.
- Hooks reference: `additionalContext` for `SessionStart` and `SubagentStart`
  (code.claude.com/docs/en/hooks), via context7.
- `plugins/devops-core/**`, `claude/scripts/block-*.sh`, `claude/tests/guards.sh`,
  `claude/settings.json`, `claude/install.sh`, `README.md`.

## Validation Plan

```bash
bash claude/tests/guards.sh
git ls-files -z '*.sh' | xargs -0 shellcheck --severity=warning
jq empty claude/settings.json .claude-plugin/marketplace.json \
  plugins/*/.claude-plugin/plugin.json plugins/*/hooks/hooks.json
claude plugin validate . && claude plugin validate plugins/morph && claude plugin validate plugins/devops
grep -rniE 'terraform|helm|kubectl|eks|argocd|aurora|aws' plugins/morph   # expect nothing domain-specific

M=./plugins/morph; D=./plugins/devops
# naming in the guard log: agent_type=morph:morph agent_id=no; morph:investigator agent_id=yes
claude -p --plugin-dir $M --agent morph:morph \
  "Run git status, then ask morph:investigator to run: echo sub" </dev/null
# morph alone (devops off): no aws tools, no devops brief, works end to end
claude -p --plugin-dir $M --agent morph:morph "List your mcp__ tools and any domain brief you received" </dev/null
# installer, isolated
C=$TMPDIR/inst; cp claude/settings.json "$TMPDIR/before.json"
CLAUDE_CONFIG_DIR=$C AGENT_CONFIG_MARKETPLACE=$PWD bash claude/install.sh
cmp "$TMPDIR/before.json" claude/settings.json && [ -L "$C/settings.json" ]
```

Before/after behaviour test, same prompt, no hint about skills, in a scratch
git repository with a small Terraform module:
"Add a `flow_log` to the VPC module and validate the change; do not apply."
- Before (`devops-core:devops`, today's `main`): record which commands it runs.
- After (`morph:morph` with `devops` loaded): it must load `devops:terraform`
  and run at least the same validation (`fmt -recursive -check`, `validate`,
  `plan`), and must not run `apply`.
- After with `devops` switched off (`morph` alone): no `devops:*` skill and no
  brief; it must still plan, ask, and refuse `apply`.

## Before result (2026-10-29, `devops-core:devops`, sonnet, `--permission-mode acceptEdits`)

Prompt: "Add a VPC flow log to the module in modules/vpc and validate the
change. Do not apply anything. You have approval to make the change in this
scratch repository without asking first; commit nothing."

- Edits: new `modules/vpc/flow_log.tf` (log group, IAM role and policy,
  `aws_flow_log`), two variables in `variables.tf`; no provider block.
- Commands: `terraform init -backend=false`, `terraform validate` (failed: the
  aws provider's plugin handshake, under the Bash sandbox), a retry with
  `CHECKPOINT_DISABLE=1` stopped at a prompt. No `terraform fmt`, no `apply`.
- Hand-back named the open validation and the untracked `.terraform/`.

The after run must match or beat this: same edits in kind, at least `init` and
`validate` attempted, and `fmt -check` added only if the `devops:terraform`
skill asks for it.
