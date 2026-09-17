# agent-config

My Claude Code configuration: settings, subagents, a Bash safety hook and MCP
servers, installed by script instead of copy-paste.

```bash
git clone https://github.com/User-Piotr/agent-config.git
cd agent-config
cp .env.example .env    # only needed for MCP servers that take a key
./install.sh
```

Restart Claude Code afterwards; hooks and `env` are read once at session start.

```
install.sh     dispatcher; one directory per agent CLI
claude/
  install.sh         links this directory into ~/.claude
  settings.json      model, theme, hooks, plugins
  CLAUDE.md          global instructions
  agents/            devops, devops-implementer, troubleshooter, devops-reviewer
  scripts/           the PreToolUse guard and the two learnings hooks
```

`settings.json` sets `"agent": "devops"`, so every session starts as that
subagent — its prompt replaces the default one entirely. Drop the key to get a
stock session back, or override it per repository in `.claude/settings.local.json`.

Everything is symlinked, so changes flow both ways: edit the repo and Claude
Code picks it up next session; change something through `/config` or a plugin
install and it shows up as a `git diff`. Nothing to run to pull it back. Paths
in `settings.json` use `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, expanded by the
shell that runs them, so there is no templating step.

Left out on purpose: `settings.local.json` (machine-local, and Headroom
rewrites it) and API keys (`.env` is gitignored; `settings.json` holds none).

`claude/scripts/block-mutations.sh` gates every Bash call. Dry-runs, plans and
`git commit` pass; `git push`, `gh` writes and live mutations ask first, and are
denied outright for headless subagents, which cannot answer a prompt. Its header
comment has the exact categories. Text matching, not a shell parser — keep
least-privilege credentials behind it.

Two layers, not one. The sandbox bounds **Bash** only — writes to the working
tree, reads everywhere but the denied paths. The `Read` and `Write` tools go
through `permissions` instead, so a sandbox denial on a path says nothing about
whether Claude can edit that path with a tool. The `permissions.deny` list is
what covers credentials, shell rc files and `.env`. Claude Code consults only
`Read(...)` and `Edit(...)` path rules; a `Write(...)` or `MultiEdit(...)` rule
is accepted and then ignored, with a warning at startup. `Edit` covers `Write`
and `NotebookEdit` too.

Needs `bash`, `jq`, `git`, `uv`, `node`, and the `claude` CLI on `PATH`. On
Linux and WSL2 the Bash sandbox also needs `bubblewrap` and `socat`, or Claude
Code warns once and runs commands unsandboxed; macOS needs neither, since
Seatbelt is part of the OS.
