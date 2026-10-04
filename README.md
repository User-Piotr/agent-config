# agent-config

My Claude Code setup: a DevOps agent with three subagents, mutation guards, a
learnings loop and a delivery skill, installed by script instead of copy-paste.

## Install

```bash
git clone https://github.com/User-Piotr/agent-config.git ~/Repositories/agent-config
cd ~/Repositories/agent-config
cp .env.example .env    # only for MCP servers that take a key
./install.sh
```

Clone somewhere permanent. `install.sh` symlinks into `~/.claude`, so the clone
*is* the installed config; a clone under `/tmp` leaves dangling links after the
next reboot. Restart Claude Code after the first install.

## What's inside

```
install.sh        dispatcher, one directory per agent CLI
claude/
  install.sh      links this directory into ~/.claude
  settings.json   model, hooks, sandbox, permissions
  CLAUDE.md       global instructions; graphify writes its block here
  agents/         devops (main), devops-implementer, troubleshooter, devops-reviewer
  skills/         delivery: branch, commit and pull request conventions
  scripts/        mutation guards for Bash and MCP, the two learnings hooks
  docs/           learnings.md, the learnings policy, read on demand
  tests/          guards.sh, the table the guards are checked against
```

Every session starts as `devops` (`"agent": "devops"` in `settings.json`). Drop
the key for a stock session, or override it per repository in
`.claude/settings.local.json`.

## MCP servers

`install.sh` registers two, both read-only and both on the MCP guard's
read-only list:

- **context7** — current docs for tools, frameworks and libraries.
- **aws-documentation** — AWS service docs, quotas and API references.

`devops`, `devops-implementer` and `troubleshooter` get both. Subagents list
each MCP tool by its full name in `tools:`; a server-wide wildcard there is not
documented, so it is not relied on.

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
decision about the plugin.

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

`~/.claude` holds symlinks, so changes flow both ways: an edit here is live, and
a change made through `/config` or a plugin install shows up as a `git diff`.
A **new** file is the exception: rerun `./install.sh` after adding an agent,
skill, script or doc, or it silently does not exist.

Machine-local state stays out of the repo. `install.sh` adds
`settings.local.json`, agent memory, Headroom's wrap files and the learnings
review file to the global gitignore; API keys live in `.env`, ignored too.

## Safety

- `block-mutations.sh` reads every Bash call. Reads, plans, dry-runs and
  `git commit` pass. Live mutations, `git push`, and `gh` or `az repos` writes
  ask first, and are denied outright for any subagent, which cannot answer a
  prompt. It matches text: `./deploy.sh` or `make apply` pass unseen, so keep
  least-privilege credentials behind it where you can.
- `block-mcp-mutations.sh` does the same for MCP tools, judged by tool name.
- Both log each decision to `~/.claude/logs/`, recording the judged binary or
  tool name, never the full command line.
- `bash claude/tests/guards.sh` runs both guards against a table of real
  command shapes. Run it after touching either script.

The sandbox and `permissions` are separate, but coupled in one direction: a
`Read(...)` rule in `permissions.deny` also blocks that path inside the Bash
sandbox. Deny a CLI's credential file and the CLI stops working. Only `Read(...)`
and `Edit(...)` path rules take effect; `Write(...)` is accepted and ignored.

## Learnings loop

When a session ends, a headless child reads the transcript and appends a dated
proposal to `.claude/claude-md-review.md` in that repository. The next session
there raises what is still unapplied. Nothing reaches `AGENTS.md` until you move
it; mark the entry `— APPLIED` when you do. The review file stays local.

## Requirements

`bash`, `jq`, `git`, `uv`, `node` and the `claude` CLI. On Linux and WSL2 the
sandbox also needs `bubblewrap` and `socat`; without them Claude Code warns once
and runs commands unsandboxed. macOS needs neither.
