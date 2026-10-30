# Rename the project, repository and marketplace to `morph`

## Summary

`agent-config` becomes `morph` everywhere: the GitHub repository
(`User-Piotr/morph`), the local clone (`~/Repositories/morph`), the plugin
marketplace (`morph`), and therefore the plugin ids (`morph@morph`,
`devops@morph`). Every machine migrates once, through `install.sh`.

## Steps

1. **Marketplace and plugins.** `.claude-plugin/marketplace.json` name `morph`;
   `plugins/devops/.claude-plugin/plugin.json` depends on `morph@morph`.
2. **Settings.** `enabledPlugins` `morph@morph`, `devops@morph` (off, as
   before); `extraKnownMarketplaces.morph` → `github` `User-Piotr/morph`,
   `autoUpdate: true`; the `agent-config` entries go. Written by the CLI in an
   isolated `CLAUDE_CONFIG_DIR` so the file stays in the CLI's format.
3. **Installer.** Plugin ids and marketplace name `morph`; the override
   variable becomes `MORPH_MARKETPLACE` (old `AGENT_CONFIG_MARKETPLACE` still
   read). Migration, when the old marketplace is present: uninstall
   `devops@agent-config`, `morph@agent-config` and `devops-core@agent-config`,
   remove the `agent-config` marketplace, install from `morph`. Same
   save/restore of `settings.json` as today. The devops on/off choice cannot be
   carried over (the pull already replaced the ids in the tracked file); the
   installer prints how to switch it on.
4. **Docs and art.** README, `docs/reference.md`, the diagram's title: name,
   clone URL `github.com/User-Piotr/morph`, path `~/Repositories/morph`,
   plugin ids. Historical plan files stay as written.

## Risks & Mitigations

- **Dangling links** between moving the clone and rerunning `install.sh`: the
  rollout does both in one step.
- **Old marketplace source**: GitHub redirects `User-Piotr/agent-config` to the
  renamed repository, so a machine not yet migrated keeps updating until it is.
  Do not create a new repository named `agent-config` while any machine is on it.
- **Lost `devops` choice**: switch it on again in `/plugin` after migrating,
  or commit `"devops@morph": true` in this change to make it the default.

## Validation Plan

```bash
bash claude/tests/guards.sh
jq empty claude/settings.json .claude-plugin/marketplace.json plugins/*/.claude-plugin/plugin.json
claude plugin validate . && claude plugin validate plugins/morph && claude plugin validate plugins/devops
git grep -n agent-config -- ':!.claude/plans'      # only the migration code
# migration, isolated: install the old marketplace from main, enable devops, then run the new installer
```

## Rollout (user)

1. Merge `chore/readme-and-terraform-sandbox`, then this branch.
2. `gh repo rename morph` (from the clone; GitHub keeps a redirect).
3. `mv ~/Repositories/agent-config ~/Repositories/morph && cd ~/Repositories/morph`
   `git remote set-url origin https://github.com/User-Piotr/morph.git && git pull`
   `./install.sh`
