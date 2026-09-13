# agent-config

Versioned configuration for my AI coding agents: Claude Code settings, subagents, safety hooks and MCP servers, installed by script instead of copy-paste.

```bash
git clone https://github.com/PiotrKmiecikBLCK/agent-config.git
cd agent-config
cp .env.example .env    # optional, only for keyed MCP servers
./install.sh
```

Restart Claude Code afterwards — hooks and `env` are read once at session start.

## Layout

```
install.sh     dispatcher; one tool directory per agent CLI
claude/
  install.sh         links this directory into ~/.claude
  settings.json      model, theme, hooks, plugins, MCP policy
  CLAUDE.md          global instructions
  agents/            devops, devops-implementer, troubleshooter
  scripts/           block-mutations.sh, the PreToolUse guard
```

## How it stays in sync

Everything is symlinked into `~/.claude`, so edits go both ways: change a file
in the repo and Claude Code picks it up on the next session; change it through
Claude Code (`/config`, installing a plugin) and it shows up as a `git diff`.
There is nothing to run to pull changes back.

Two things are deliberately left out of the repo:

- **`settings.local.json`** — machine-local, and Headroom rewrites it anyway.
- **API keys** — `.env` is gitignored. `settings.json` carries no secrets.

Paths inside `settings.json` use `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, expanded
by the shell that runs the hook, so the file is portable with no templating.

## The safety hook

`claude/scripts/block-mutations.sh` runs as a `PreToolUse` hook on every Bash
call and sorts commands into three outcomes:

| Command | Interactive session | Headless subagent |
|---|---|---|
| `git commit`, `terraform plan`, `helm template`, `kubectl diff`, any `--dry-run` | runs | runs |
| `git push`, `gh pr create` and other `gh` writes | asks | denied |
| `terraform apply/destroy`, `helm install/upgrade/delete`, `kubectl apply/delete/patch/scale`, `argocd app sync` | asks | denied |

Headless subagents get a hard deny because nothing can confirm a prompt on
their behalf; they hand work back as working-tree edits instead. The matching
is text-based over each `&&`/`||`/`;`/`|`/`$()` segment, not a real shell
parser, so pair it with least-privilege credentials rather than trusting it
alone. It fails closed if `jq` is missing.

## Requirements

`bash`, `jq`, `git`, `uv`, `node` (for `npx`), and the `claude` CLI on `PATH`.
