#!/usr/bin/env bash
# Install this directory's Claude Code configuration into ~/.claude.
# See ../README.md for what lands where and why.
set -euo pipefail
shopt -s nullglob   # an empty directory must skip its loop, not link a literal glob

CONF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BACKUP_DIR="$CLAUDE_HOME/.config-backup/$(date +%Y%m%d-%H%M%S)"

log()  { printf '  %s\n' "$*"; }
step() { printf '\n%s\n' "$*"; }

link() {
  local src="$1" dst="$CLAUDE_HOME/$2"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mkdir -p "$BACKUP_DIR"
    mv "$dst" "$BACKUP_DIR/"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"
  log "$2"
}

step "Linking config"
link "$CONF_DIR/CLAUDE.md"                 CLAUDE.md
link "$CONF_DIR/settings.json"             settings.json
for f in "$CONF_DIR"/agents/*.md; do
  link "$f" "agents/$(basename "$f")"
done
for f in "$CONF_DIR"/scripts/*.sh; do
  link "$f" "scripts/$(basename "$f")"
  chmod +x "$f"
done
for f in "$CONF_DIR"/docs/*.md; do
  link "$f" "docs/$(basename "$f")"
done
for d in "$CONF_DIR"/skills/*/; do
  link "${d%/}" "skills/$(basename "$d")"
done

step "Statusline"
# Copied from the installed caveman plugin rather than vendored, so it cannot
# go stale. The plugin's own installer uses this same destination.
src=$(find "$CLAUDE_HOME/plugins/cache/caveman" -name caveman-statusline.sh -print -quit 2>/dev/null || true)
if [ -n "$src" ]; then
  # cp, not `install -D`: -D is GNU-only, and BSD install on macOS fails with
  # "No such file or directory" on its own temp file when the target directory
  # does not exist yet.
  mkdir -p "$CLAUDE_HOME/hooks"
  cp "$src" "$CLAUDE_HOME/hooks/caveman-statusline.sh"
  chmod 755 "$CLAUDE_HOME/hooks/caveman-statusline.sh"
  log "from $src"
else
  log "caveman plugin not cloned yet — rerun after Claude Code restarts"
fi

step "MCP servers"
INSTALLED=$(claude mcp list 2>/dev/null || true)
add_mcp() {
  case "$INSTALLED" in
    *"$1:"*) log "$1 present"; return ;;
  esac
  claude mcp add-json "$1" "$2" --scope user >/dev/null && log "added $1"
}

# MCP_USER_AGENT: docs.aws.amazon.com rejects the default agent string.
add_mcp awslabs.aws-documentation-mcp-server '{
  "command": "uvx",
  "args": ["awslabs.aws-documentation-mcp-server@latest"],
  "env": {
    "FASTMCP_LOG_LEVEL": "ERROR",
    "AWS_DOCUMENTATION_PARTITION": "aws",
    "MCP_USER_AGENT": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
  }
}'

if [ -n "${CONTEXT7_API_KEY:-}" ]; then
  # The key goes in env, not args: an argument is visible to anyone who runs
  # `ps`, an environment variable is not. The package reads CONTEXT7_API_KEY.
  add_mcp context7 "{
    \"command\": \"npx\",
    \"args\": [\"-y\", \"@upstash/context7-mcp\"],
    \"env\": {\"CONTEXT7_API_KEY\": \"$CONTEXT7_API_KEY\"}
  }"
else
  # Already registered is the normal case on a machine that has been set up;
  # only a first install actually needs the key.
  case "$INSTALLED" in
    *"context7:"*) log "context7 present" ;;
    *)             log "context7 skipped — set CONTEXT7_API_KEY in .env" ;;
  esac
fi

step "Global gitignore"
# Claude Code drops machine-local files next to whatever repository it runs
# in. Ignoring them once here beats editing .gitignore in every work tree.
IGNORE="$(git config --global core.excludesFile 2>/dev/null || true)"
IGNORE="${IGNORE/#\~/$HOME}"
[ -n "$IGNORE" ] || IGNORE="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
mkdir -p "$(dirname "$IGNORE")"
for pat in '.claude/settings.local.json' '.claude/agent-memory/' '.claude/.headroom_wrap_*' '.claude/claude-md-review.md'; do
  grep -qxF "$pat" "$IGNORE" 2>/dev/null || { printf '%s\n' "$pat" >> "$IGNORE"; log "$pat"; }
done
log "in $IGNORE"

step "Sandbox dependencies"
# settings.json enables the Bash sandbox. On macOS it needs nothing — Seatbelt
# is part of the OS. On Linux and WSL2 it needs bubblewrap for filesystem
# isolation and socat to relay network traffic; without both, `sandbox.enabled`
# is a no-op and Claude Code warns once, then runs commands unsandboxed.
# Not installed here because it needs root.
if [ "$(uname -s)" = "Darwin" ]; then
  log "macOS: Seatbelt is built in, nothing to install"
else
  MISSING=""
  for b in bwrap socat; do command -v "$b" >/dev/null 2>&1 || MISSING="$MISSING $b"; done
  if [ -n "$MISSING" ]; then
    log "missing:$MISSING"
    log "install with: sudo apt-get install$MISSING"
  else
    log "bubblewrap and socat present"
  fi
fi

step "Headroom and skills"
# `headroom init claude` owns its whole integration: the MCP entry, the
# ANTHROPIC_BASE_URL routing, and the SessionStart selfheal hook. It writes the
# machine-local parts to settings.local.json, which stays untracked.
command -v headroom  >/dev/null || uv tool install headroom-ai
command -v graphify  >/dev/null || { uv tool install graphifyy && graphify install --platform claude; }
# --global belongs to `init`, not to `claude`: click puts group options before
# the subcommand, so `headroom init claude --global` fails with "No such option".
headroom init --global claude
log "verify with: headroom doctor"

step "Done"
log "restart Claude Code to pick up hooks and env changes"
[ -d "$BACKUP_DIR" ] && log "files replaced on first install are in $BACKUP_DIR"
exit 0
