#!/usr/bin/env bash
# Install this directory's Claude Code configuration into ~/.claude.
# See ../README.md for what lands where and why.
set -euo pipefail

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

step "Statusline"
# Copied from the installed caveman plugin rather than vendored, so it cannot
# go stale. The plugin's own installer uses this same destination.
src=$(find "$CLAUDE_HOME/plugins/cache/caveman" -name caveman-statusline.sh -print -quit 2>/dev/null || true)
if [ -n "$src" ]; then
  install -Dm755 "$src" "$CLAUDE_HOME/hooks/caveman-statusline.sh"
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
  add_mcp context7 "{
    \"command\": \"npx\",
    \"args\": [\"-y\", \"@upstash/context7-mcp\", \"--api-key\", \"$CONTEXT7_API_KEY\"]
  }"
else
  log "context7 skipped — set CONTEXT7_API_KEY in .env"
fi

step "Headroom and skills"
# `headroom init claude` owns its whole integration: the MCP entry, the
# ANTHROPIC_BASE_URL routing, and the SessionStart selfheal hook. It writes the
# machine-local parts to settings.local.json, which stays untracked.
command -v headroom  >/dev/null || uv tool install headroom-ai
command -v graphify  >/dev/null || { uv tool install graphifyy && graphify install --platform claude; }
headroom init claude --global
log "verify with: headroom doctor"

step "Done"
log "restart Claude Code to pick up hooks and env changes"
[ -d "$BACKUP_DIR" ] && log "files replaced on first install are in $BACKUP_DIR"
exit 0
