# Ship the agent setup as the `devops-core` plugin

## Summary

Move the content of this setup — agents, skills, the learnings loop and the
read-only documentation MCP servers — into a Claude Code plugin, `devops-core`,
published from this repository as the `agent-config` marketplace. Policy
(sandbox, permissions, the mutation guards) stays in `settings.json`, which a
plugin cannot carry and which must not be switchable off with one click in
`/plugin`. A team extends the setup with its own plugin that depends on
`devops-core` (its MCP servers, its skills) instead of forking it.

## Inventory

| Today | Goes to | Notes |
|---|---|---|
| `claude/agents/{devops,devops-implementer,troubleshooter,devops-reviewer}.md` | `plugins/devops-core/agents/` | names become `devops-core:<name>` |
| `claude/skills/delivery/` | `plugins/devops-core/skills/delivery/` | `devops-core:delivery` |
| `claude/docs/learnings.md` | `plugins/devops-core/skills/learnings/SKILL.md` | a skill, because an agent prompt cannot resolve the plugin's path |
| `claude/scripts/learnings-{pending,queue}.sh` | `plugins/devops-core/scripts/` + `hooks/hooks.json` | |
| context7, aws-documentation MCP | `plugin.json` `mcpServers` | context7 key through `userConfig` |
| `claude/scripts/block-{mutations,mcp-mutations}.sh`, `claude/tests/guards.sh` | stay | policy; linked into `~/.claude/scripts/` |
| `claude/settings.json` | stays | sandbox, permissions, model, guards' hooks, enabled plugins |
| `claude/CLAUDE.md` | stays | a plugin cannot ship the global CLAUDE.md |
| `install.sh`, `claude/install.sh`, `.env.example`, CI, README, GRAPHIFY.md | stay | installer shrinks |
| headroom MCP | neither | `headroom wrap claude` registers it on every run (`_setup_headroom_mcp`) |
| serena | neither | comes with headroom (`headroom wrap` sets it up), not installed on its own |

## Verified (spike on `feat/plugin-spike`, Claude Code 2.1.289)

1. A plugin agent reaches hooks as `agent_type=devops-core:<name>`: top-level
   with `agent_id` absent, as a subagent with `agent_id` set.
2. A plugin MCP tool is `mcp__plugin_devops-core_<server>__<tool>`; the MCP
   guard reads its server as `plugin_devops-core_<server>`.
3. `claude plugin configure <plugin> --values-stdin` sets a sensitive
   `userConfig` value without the TUI. It does not appear in `~/.claude.json`,
   `~/.claude/plugins/` or any settings file, nor in the server's command line.
4. A plugin subagent with only `disallowedTools` inherits every MCP tool of the
   session, including another plugin's (`mcp__plugin_devops-core_context7__*`
   seen next to the user-scope servers).
5. A plugin subagent sees skills from a second plugin that depends on
   `devops-core` (`spike-ext:grafana-triage`), loaded side by side.
6. Plugin `SessionStart` and `SessionEnd` hooks fire in `claude -p` with
   `CLAUDE_PLUGIN_ROOT` set to the plugin directory.
7. **`claude plugin marketplace add` and `claude plugin install` at user scope
   rewrite `~/.claude/settings.json` even when the keys are already declared**:
   keys reordered, and `"model": "opus"` normalised to `"opus[1m]"`.
   `marketplace update` and `plugin update` do not write it. Restoring the
   file's previous content after installing leaves the plugin enabled.

From the documentation, not tested:

- With no `version` in the manifest or marketplace entry, a plugin in a
  git-hosted marketplace is versioned by commit SHA, so every push is an update.
  A pinned `version` freezes users until it is bumped.
- Auto-update is off by default for third-party marketplaces.
- For plugin agents, `mcpServers`, `hooks`, `permissionMode` and
  `initialPrompt` in frontmatter are ignored.
- The plugin's own `settings.json` honours only `agent` and
  `subagentStatusLine`, and user settings override it.

Observed during implementation: `memory: local` keeps a plugin agent's notes
in `.claude/agent-memory-local/devops-core-<agent>/` (the colon becomes a dash).
`memory` also enables Read, Write and Edit for the agent, so `troubleshooter`
had them before the switch to `disallowedTools` as well; listing them as
disallowed would break its memory. Its read-only promise rests on its prompt,
as before.

Still open: installing a team plugin from a private Azure DevOps marketplace.

## Steps

1. **Plugin and marketplace.** `.claude-plugin/marketplace.json` at the repo
   root (`agent-config`, one entry `devops-core` → `./plugins/devops-core`).
   `plugins/devops-core/.claude-plugin/plugin.json` with no `version`,
   `userConfig.context7_api_key` (sensitive), and `mcpServers` `context7`
   (`env.CONTEXT7_API_KEY` from `${user_config.context7_api_key}`) and
   `aws-documentation` (the env block `install.sh` uses today).
   `plugins/devops-core/settings.json` with `{"agent": "devops"}`.
   `git mv` the four agents, `skills/delivery`, and `docs/learnings.md` →
   `skills/learnings/SKILL.md` (add the skill frontmatter). Delete the spike's
   `probe` agent, `spike-core` skill and echo hooks.

2. **Agent content.**
   - `troubleshooter` and `devops-implementer`: replace the `tools:` allowlist
     with `disallowedTools:` (at least `NotebookEdit` and `Agent`; keep what each
     must not do), so they inherit MCP tools from any enabled plugin.
     `devops-reviewer` keeps `tools: Read, Glob, Grep, Bash`.
   - `troubleshooter` must not gain an editing path through inheritance: the MCP
     guard allows serena's editing tools for subagents (it is on
     `READ_ONLY_SERVERS` so the implementer can use it, and it is present
     wherever headroom's `wrap` set it up), so its
     `disallowedTools` also lists `mcp__serena__*`. Check every other inherited
     server for tools that write and list them the same way.
   - Every reference to another agent or skill uses the plugin name:
     `devops-core:devops-implementer`, `devops-core:troubleshooter`,
     `devops-core:devops-reviewer`, `devops-core:delivery`,
     `devops-core:learnings` (replacing "read `~/.claude/docs/learnings.md`").
   - MCP tool names in prose become `mcp__plugin_devops-core_context7` and
     `mcp__plugin_devops-core_aws-documentation`.
   - `troubleshooter` gains one generic line in its investigation step: before
     searching from scratch, check whether an available skill covers the system
     under investigation.
   - The memory directory path quoted in `devops.md` and `devops-implementer.md`
     is corrected to what Claude Code creates for a plugin agent — observe it,
     do not guess.

3. **Learnings hooks into the plugin.** Move both scripts to
   `plugins/devops-core/scripts/`; register them in `hooks/hooks.json`
   (`SessionStart` matcher `startup|resume`, `SessionEnd`) as
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh"`. `POLICY` in
   `learnings-queue.sh` becomes `${CLAUDE_PLUGIN_ROOT}/skills/learnings/SKILL.md`.
   Remove both hooks from `claude/settings.json`.

4. **Guards.** `INTERACTIVE_AGENTS=("devops" "devops-core:devops")` in both
   guards; `"devops"` stays until every machine has migrated. Add
   `plugin_devops-core_context7` and `plugin_devops-core_aws-documentation` to
   `READ_ONLY_SERVERS` as exact names — no prefix stripping, so another plugin
   cannot borrow a trusted server name. New rows in `claude/tests/guards.sh`:
   `top:devops-core:devops` asks, `sub:devops-core:troubleshooter` is denied, a
   top-level `devops-core:anything-else` is denied, both plugin servers allow.

5. **Settings.** In `claude/settings.json`: `"agent": "devops-core:devops"`
   (explicit, so the result does not depend on plugin-default precedence),
   `"devops-core@agent-config": true` in `enabledPlugins`, and the `agent-config`
   marketplace (`github`, `User-Piotr/agent-config`) in `extraKnownMarketplaces`,
   with auto-update on if the marketplace entry supports it (check the key in
   the marketplace reference; otherwise document `claude plugin update`).

6. **Installer.** In `claude/install.sh`:
   - Link only `CLAUDE.md`, `settings.json` and the two guard scripts. Remove
     the symlinks it created before under `~/.claude/{agents,skills,docs,scripts}`
     — only symlinks that resolve into this repository.
   - Drop the `add_mcp` calls for context7 and aws-documentation; remove those
     two user-scope registrations when present (`claude mcp remove ... --scope user`).
   - Drop `headroom mcp install`; keep `uv tool install headroom-ai`. Comment:
     `headroom wrap claude` owns headroom's routing and MCP registration.
   - Install the plugin only when `claude plugin list` does not show it:
     save the content of `settings.json`, run `claude plugin marketplace add
     User-Piotr/agent-config` and `claude plugin install devops-core@agent-config`,
     then write the saved content back through the symlink (finding 7) and
     confirm the plugin still lists as enabled.
   - When `.env` sets `CONTEXT7_API_KEY`, pass it on stdin:
     `jq -n --arg k "$CONTEXT7_API_KEY" '{context7_api_key:$k}' | claude plugin
     configure devops-core@agent-config --values-stdin` — never as an argument.

7. **CI and docs.** In `.github/workflows/checks.yml`, run
   `claude plugin validate .` and `claude plugin validate plugins/devops-core`
   if the CLI installs cleanly on the runner (else document it as a local
   check). README: new layout; what lives in the plugin and what in
   `settings.json`, and why; headroom managed by `wrap`; "Add your own plugin",
   using a Grafana MCP server, `userConfig` for URL and token, and a
   `grafana-triage` skill as the example; how updates arrive; "Gateway or
  Bedrock": agents keep the `opus` / `sonnet` aliases, and the mapping lives in
  settings `env`, never in the plugin — `ANTHROPIC_BASE_URL` and
  `ANTHROPIC_AUTH_TOKEN` for a LiteLLM gateway, `ANTHROPIC_DEFAULT_OPUS_MODEL`,
  `ANTHROPIC_DEFAULT_SONNET_MODEL` and `ANTHROPIC_DEFAULT_HAIKU_MODEL` (Haiku is
  used for background work even when no agent names it); the gateway must pass
  `anthropic-beta` headers through for 1M context and tool search; with
  headroom in front, headroom's upstream must point at the gateway (option name
  to be confirmed in headroom before documenting it).

Implement as two delegations against this file: steps 1–4, then 5–7.

## Risks & Mitigations

- **Main session hard-denied** once the agent is named `devops-core:devops`.
  Step 4 lands with step 1 in the same PR; guard rows cover both names.
- **Tracked `settings.json` rewritten by the plugin CLI** (finding 7). Step 6
  restores it; any later `/plugin install` by hand shows up in `git diff` and is
  reverted the same way. README says so.
- **Duplicate agents and servers** on a half-migrated machine (`devops` next to
  `devops-core:devops`, two context7). Step 6 cleans up; README lists the manual
  commands.
- **Wider tool reach** for `troubleshooter` and `devops-implementer` after the
  switch to `disallowedTools`. Covered by the subagent hard-deny in both guards
  and by the sandbox, except where a server is trusted wholesale on
  `READ_ONLY_SERVERS` while it can write (serena): those go into
  `troubleshooter`'s `disallowedTools`. `devops-reviewer` stays narrow.
- **Stale plugin copies**: third-party auto-update is off by default; step 5
  turns it on or the README documents `claude plugin update`.
- **Blast radius**: every team member's `~/.claude`. Roll out on one machine
  first. Rollback: check out the last pre-plugin tag and rerun `install.sh`
  after `claude plugin uninstall devops-core@agent-config`.

## References

- Spike: `.claude-plugin/`, `plugins/devops-core/`, `~/.cache/spike-ext/`.
- code.claude.com/docs/en/plugins — components, manifest reference, marketplace
  reference, loading (versions and updates), install (auto-update); sub-agents
  (`tools`, `disallowedTools`, fields ignored for plugin agents). Via context7.
- `claude/scripts/block-mutations.sh`, `claude/scripts/block-mcp-mutations.sh`,
  `claude/tests/guards.sh`, `claude/install.sh`, `claude/settings.json`.
- headroom 0.41.0 `cli/wrap.py` `_setup_headroom_mcp`.

## Validation Plan

```bash
bash claude/tests/guards.sh
git ls-files -z '*.sh' | xargs -0 shellcheck --severity=warning
jq empty claude/settings.json .claude-plugin/marketplace.json \
  plugins/devops-core/.claude-plugin/plugin.json plugins/devops-core/hooks/hooks.json
claude plugin validate .
claude plugin validate plugins/devops-core

P=./plugins/devops-core
# top-level name in the guard log: agent_type=devops-core:devops agent_id=no
claude -p --plugin-dir $P --agent devops-core:devops "Run: git status" </dev/null
# subagent name, inherited plugin MCP tools, skills from the plugin
claude -p --plugin-dir $P --agent devops-core:devops \
  "Spawn devops-core:troubleshooter. Ask it to list its tools containing 'mcp__' and its available skills, and to run: echo sub" </dev/null
# learnings hooks fire from the plugin root (learnings.log gains a line on exit in a git repo)
# installer, isolated from the real ~/.claude, against the working copy:
C=$TMPDIR/inst; cp claude/settings.json "$TMPDIR/before.json"
CLAUDE_CONFIG_DIR=$C AGENT_CONFIG_MARKETPLACE=$PWD bash claude/install.sh
cmp "$TMPDIR/before.json" claude/settings.json   # repository file byte-identical
[ -L "$C/settings.json" ]                        # still a symlink, not a rewritten copy
CLAUDE_CONFIG_DIR=$C claude plugin list | grep -A4 devops-core   # Status: enabled
# memory directory name, as the agent reports it
claude -p --plugin-dir $P --agent devops-core:devops \
  "Ask devops-core:troubleshooter for the absolute path of its memory directory" </dev/null
# learnings loop, after a real session ends in a git repository:
tail -1 ~/.claude/logs/learnings.log   # a line with cost_usd= and the outcome
```

Live, on one machine after merge: fresh session in a repository; `/agents`
lists only `devops-core:*`; `/mcp` shows one context7 with no key in its
arguments; `/plugin` shows `devops-core` enabled; a `terraform apply` request
still prompts; plan mode writes to `.claude/plans/`.
