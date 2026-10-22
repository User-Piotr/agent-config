# agent-config

My Claude Code setup in two parts. The **`devops-core` plugin** carries the
content: a DevOps agent with three subagents, the delivery and learnings skills,
the learnings loop, and read-only documentation MCP servers. **`claude/`**
carries the policy a plugin cannot or should not: sandbox, permissions, the
mutation guards and the global instructions. This repository is also the
`agent-config` plugin marketplace, so a team extends the setup with a plugin of
its own instead of a fork.

## Install

```bash
git clone https://github.com/User-Piotr/agent-config.git ~/Repositories/agent-config
cd ~/Repositories/agent-config
cp .env.example .env    # optional: CONTEXT7_API_KEY
./install.sh
```

Clone somewhere permanent. `install.sh` symlinks the policy files into
`~/.claude`, so the clone *is* the installed policy; a clone under `/tmp` leaves
dangling links after the next reboot. It also installs the plugin from GitHub
and, when `.env` has a key, stores it as the plugin's context7 option. Restart
Claude Code after the first install.

### Moving a machine from the pre-plugin layout

`git pull` and `./install.sh` do it: the installer removes its old links under
`~/.claude/{agents,skills,docs,scripts}`, installs the plugin, and drops the
user-scope `context7` and `awslabs.aws-documentation-mcp-server` registrations
the plugin replaces. If it stopped halfway, finish by hand:

```bash
find ~/.claude/agents ~/.claude/skills ~/.claude/docs ~/.claude/scripts -xtype l -delete
claude mcp remove context7 --scope user
claude mcp remove awslabs.aws-documentation-mcp-server --scope user
claude plugin install devops-core@agent-config && git checkout claude/settings.json
```

Agent memory moves with the new names: `memory: local` keeps a plugin agent's
notes in `.claude/agent-memory-local/devops-core-<agent>/`. To keep what an
agent already learned in a repository, rename its directory there, e.g.
`mv .claude/agent-memory-local/{devops-implementer,devops-core-devops-implementer}`.

### The plugin alone

Without this repository's policy:
`/plugin marketplace add User-Piotr/agent-config`, then
`/plugin install devops-core@agent-config`.

## What's inside

```
install.sh                 dispatcher, one directory per agent CLI
.claude-plugin/            marketplace.json: this repository as the agent-config marketplace
plugins/devops-core/       the plugin
  .claude-plugin/          plugin.json: MCP servers, the context7 key option
  agents/                  devops (main), devops-implementer, troubleshooter, devops-reviewer
  skills/                  delivery (branch, commit, PR conventions), learnings (the policy)
  hooks/, scripts/         the learnings loop
claude/                    policy, linked into ~/.claude
  install.sh               links policy, installs the plugin
  settings.json            model, sandbox, permissions, guard hooks, enabled plugins
  CLAUDE.md                global instructions; graphify writes its block here
  scripts/                 mutation guards for Bash and MCP
  tests/                   guards.sh, the table the guards are checked against
```

Plugin names are prefixed: the agents are `devops-core:devops`,
`devops-core:troubleshooter` and so on, the skills `devops-core:delivery` and
`devops-core:learnings`. Every session starts as `devops-core:devops`
(`"agent"` in `settings.json`). Drop the key for a stock session, or override it
per repository in `.claude/settings.local.json`.

Why the split: a plugin can carry agents, skills, hooks and MCP servers, but its
settings honour only `agent` and `subagentStatusLine`. Sandbox, permissions and
model stay in `settings.json`. The guards could ship in the plugin, but a plugin
is one click away from disabled in `/plugin`, and a safety layer must not be.

## MCP servers

All three are read-only and on the MCP guard's read-only list:

- **context7** (plugin) — current docs for tools, frameworks and libraries. Its
  key is a sensitive plugin option, kept out of settings files and process
  arguments; set it with `/plugin configure devops-core@agent-config`.
- **aws-documentation** (plugin) — AWS service docs, quotas and API references.
- **headroom** (`headroom wrap claude`) — `headroom_compress`,
  `headroom_retrieve` and `headroom_stats`, which pair with the Headroom proxy.
  `wrap` registers it on every run, and serena with it.

A plugin's tools are named `mcp__plugin_devops-core_<server>__<tool>`.

Traffic reaches the Headroom proxy only in sessions started with
`headroom wrap claude`; a bare `claude` goes straight to the API. `wrap` writes
its routing to the repository's untracked `.claude/settings.local.json` and
removes it when the session ends, leaving only a selfheal hook that clears a
dead proxy's address after a crash. Do not run `headroom init` in either form:
`--global` writes the routing into `~/.claude/settings.json`, which is this
repository's tracked file, and the local form adds hooks and a plugin to the
project that `wrap` does not need.

`troubleshooter` and `devops-implementer` list what they may not use
(`disallowedTools`) instead of what they may, so they inherit the MCP tools of
any enabled plugin, a team's included. Writes stay covered: both guards
hard-deny a subagent's live mutations and write-shaped MCP calls, and
`troubleshooter` also drops serena, whose editing tools the guard trusts.
`devops-reviewer` keeps a short allowlist.

## Skills

`settings.json` keeps the skill list short, because every enabled skill costs
its description in context on every turn:

- `syncClaudeAiSkills: false` drops the skills synced from claude.ai (docx,
  pptx, pdf, morning, computer-use, ...).
- `skillOverrides` switches off the bundled skills this setup does not use.
  Set a name to `"on"` to bring it back.

`skillOverrides` does not reach a plugin: its skills show as "locked by plugin"
and stay on, and so do its agents. The caveman plugin therefore loads all its
skills and its three `cavecrew-*` agents. Whether it stays is an all-or-nothing
decision about the plugin. Sessions start in its `lite` mode
(`CAVEMAN_DEFAULT_MODE` in `env`; the plugin's own default is `full`), and
`/caveman <level>` switches for the current session.

## Knowledge graph

`install.sh` installs graphify, and `graphify install --platform claude` adds
its skill and writes a block into `CLAUDE.md` — through the symlink, so that
block is part of this repository.

graphify can build its graph from code alone, with no LLM call and no network,
for the file types it parses. Coverage depends on the repository: some come out
detailed, others nearly empty until `/graphify` runs its LLM pass. Run the two
commands and check what came out before relying on the graph:

```bash
graphify update . --no-cluster
graphify cluster-only . --no-label --no-viz
```

Every query then runs offline against `graphify-out/graph.json`:

```bash
graphify affected "<node>"          # what references it, with file:line
graphify god-nodes                  # the most connected nodes
graphify query "<question>" --budget 1500
```

The output lands in `graphify-out/` at the repository root. Step-by-step
building and refreshing, including the shared multi-repository graph:
[GRAPHIFY.md](GRAPHIFY.md).

## Editing

The policy files in `~/.claude` are symlinks, so changes flow both ways: an edit
to `claude/` is live, and a change made through `/config` shows up as a
`git diff`. A new guard script needs `./install.sh` to be linked.

So does a plugin command: `claude plugin marketplace add` and
`claude plugin install` at user scope rewrite `settings.json` (keys reordered,
`"opus"` normalised to `"opus[1m]"`) even when it already declares everything.
`install.sh` writes the file back; after a manual `/plugin install`, restore it
with `git checkout claude/settings.json`.

The plugin is installed from GitHub, so edits under `plugins/` reach a machine
only after they are merged. To try them first, load the working copy for one
session: `claude --plugin-dir ./plugins/devops-core`. To test the installer on a
branch: `AGENT_CONFIG_MARKETPLACE="$PWD" ./install.sh claude`.

The plugin has no `version`, so every commit on `main` is a new version, and the
marketplace has `autoUpdate` on: a session refreshes it in the background and
the next session loads the update. `claude plugin update devops-core@agent-config`
forces it.

Machine-local state stays out of the repo. `install.sh` adds
`settings.local.json`, agent memory, Headroom's wrap files and the learnings
review file to the global gitignore; API keys live in `.env`, ignored too.

## Safety

- `block-mutations.sh` reads every Bash call. Reads, plans, dry-runs and
  `git commit` pass. Live mutations, `git push`, and `gh` or `az repos` writes
  ask first, and are denied outright for any subagent, which cannot answer a
  prompt. It matches text: `./deploy.sh` or `make apply` pass unseen, so keep
  least-privilege credentials behind it where you can.
- `permissions.ask` in `settings.json` is the second layer for the same Bash
  commands: Terraform, OpenTofu and Terragrunt state changes, helmfile, Argo CD
  app writes, `git push`, and the `gh` and `az repos` writes that publish.
  Claude Code matches these itself, inside `&&`, `$()` and loops, and they hold
  even though the sandbox auto-allows Bash. kubectl and helm are left to the
  guard alone, since a prefix rule would also prompt on every dry-run.
- `block-mcp-mutations.sh` does for MCP tools what `block-mutations.sh` does
  for Bash, judged by tool name.
- Both log each decision to `~/.claude/logs/`, recording the judged binary or
  tool name, never the full command line.
- `bash claude/tests/guards.sh` runs both guards against a table of real
  command shapes. Run it after touching either script.

The sandbox and `permissions` are separate, but coupled in one direction: a
`Read(...)` rule in `permissions.deny` also blocks that path inside the Bash
sandbox. Deny a CLI's credential file and the CLI stops working. Only `Read(...)`
and `Edit(...)` path rules take effect; `Write(...)` is accepted and ignored.

## Learnings loop

The plugin's `SessionEnd` hook starts it. When a session ends, a headless child reads the transcript and appends a dated
proposal to `.claude/claude-md-review.md` in that repository. The next session
there raises what is still unapplied. Nothing reaches `AGENTS.md` until you move
it; mark the entry `— APPLIED` when you do. The review file stays local.

## Your own plugin

A team adds its own MCP servers, skills or agents as a plugin that depends on
`devops-core`, in a marketplace of its own (any git host the team can clone
from). Nothing in this repository changes. Example: Grafana for troubleshooting.

```
team-plugins/                          the team's marketplace repository
  .claude-plugin/marketplace.json
  plugins/team/
    .claude-plugin/plugin.json
    skills/grafana-triage/SKILL.md
```

`plugin.json` declares the dependency, asks each user for the URL and token, and
defines the server:

```json
{
  "name": "team",
  "dependencies": ["devops-core@agent-config"],
  "userConfig": {
    "grafana_url":   { "type": "string", "title": "Grafana URL" },
    "grafana_token": { "type": "string", "title": "Grafana token", "sensitive": true }
  },
  "mcpServers": {
    "grafana": {
      "command": "mcp-grafana",
      "env": {
        "GRAFANA_URL": "${user_config.grafana_url}",
        "GRAFANA_API_KEY": "${user_config.grafana_token}"
      }
    }
  }
}
```

The skill carries what the agent cannot guess: which dashboards and data sources
matter for which symptom. Its `description` decides whether it is picked, so name
the symptoms — "Use when investigating latency, error rates, pod restarts or
alerts" — not just the tool.

`troubleshooter` inherits the server's tools and is told to look for a skill
covering the system under investigation. Read-shaped tool names
(`search_*`, `get_*`, `query_*`, `list_*`) pass the MCP guard; write-shaped ones
ask in the main session and are denied to subagents. A server that needs to be
trusted wholesale goes on `READ_ONLY_SERVERS` in the guard, by pull request here.

Each user adds the marketplace and enables the plugin, for example in
`.claude/settings.json` of the repositories where it applies, or with
`/plugin marketplace add` and `/plugin install`.

## Gateway or Bedrock

The agents name models by alias (`opus`, `sonnet`), so the plugin runs
unchanged behind a gateway. The mapping lives in `env` in settings — never in
the plugin, which cannot set `env`:

- `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` point Claude Code at a LiteLLM
  gateway.
- Either the gateway serves the names the aliases resolve to
  (`claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5`), or
  `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL` and
  `ANTHROPIC_DEFAULT_HAIKU_MODEL` name what it serves. Haiku is needed even
  though no agent names it: Claude Code uses it for background work.
- The gateway must pass `anthropic-beta` headers through, or the 1M context
  window and tool search stop working; without tool search every MCP tool's
  schema loads up front.
- With Headroom in front, the chain is Claude Code → Headroom → gateway →
  Bedrock: Headroom's upstream has to point at the gateway. Check Headroom's
  proxy options for the setting before relying on it.

## Requirements

`bash`, `jq`, `git`, `uv`, `node` and the `claude` CLI. On Linux and WSL2 the
sandbox also needs `bubblewrap` and `socat`; without them Claude Code warns once
and runs commands unsandboxed. macOS needs neither.
