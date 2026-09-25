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
  CLAUDE.md       global instructions
  agents/         devops (main), devops-implementer, troubleshooter, devops-reviewer
  skills/         delivery: branch, commit and pull request conventions
  scripts/        mutation guards for Bash and MCP, the two learnings hooks
  docs/           learnings.md, the learnings policy, read on demand
```

Every session starts as `devops` (`"agent": "devops"` in `settings.json`). Drop
the key for a stock session, or override it per repository in
`.claude/settings.local.json`.

## Editing

`~/.claude` holds symlinks, so changes flow both ways: an edit here is live, and
a change made through `/config` or a plugin install shows up as a `git diff`.
A **new** file is the exception: rerun `./install.sh` after adding an agent,
skill, script or doc, or it silently does not exist.

Machine-local state stays out of the repo. `install.sh` adds
`settings.local.json`, agent memory and Headroom's wrap files to the global
gitignore; API keys live in `.env`, which is ignored too.

## Safety

- `block-mutations.sh` reads every Bash call. Reads, plans, dry-runs and
  `git commit` pass. Live mutations, `git push`, and `gh` or `az repos` writes
  ask first, and are denied outright for any subagent, which cannot answer a
  prompt. It matches text: `./deploy.sh` or `make apply` pass unseen, so keep
  least-privilege credentials behind it where you can.
- `block-mcp-mutations.sh` does the same for MCP tools, judged by tool name.
- Both log each decision to `~/.claude/logs/`, recording only the first word of
  a command, never the full line.

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
