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
# Only policy is linked: the global instructions, the settings, and the two
# mutation guards. Agents, skills and the learnings loop ship in the
# morph plugin (../plugins/morph); the DevOps knowledge in the devops plugin
# (../plugins/devops). Both are installed below.
link "$CONF_DIR/CLAUDE.md"                 CLAUDE.md
link "$CONF_DIR/settings.json"             settings.json
for f in "$CONF_DIR"/scripts/*.sh; do
  link "$f" "scripts/$(basename "$f")"
  chmod +x "$f"
done

# Earlier versions linked agents/, skills/, docs/ and the learnings scripts from
# this directory. Those files moved into the plugin, so their links now point
# at nothing; a leftover agent would also shadow the plugin's under its old
# name. Remove only dangling links that point into this directory.
for l in "$CLAUDE_HOME"/agents/* "$CLAUDE_HOME"/skills/* "$CLAUDE_HOME"/docs/* "$CLAUDE_HOME"/scripts/*; do
  [ -L "$l" ] && [ ! -e "$l" ] || continue
  case "$(readlink "$l")" in
    "$CONF_DIR"/*) rm "$l"; log "removed stale ${l#"$CLAUDE_HOME"/}" ;;
  esac
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

step "Plugins"
CORE="morph@agent-config"
DOMAIN="devops@agent-config"
OLD="devops-core@agent-config"
# Override to test a branch before it is on GitHub, e.g. with a local checkout:
#   AGENT_CONFIG_MARKETPLACE="$PWD" ./install.sh claude
MARKETPLACE="${AGENT_CONFIG_MARKETPLACE:-User-Piotr/agent-config}"

# `claude plugin marketplace add` and `claude plugin install` at user scope
# rewrite ~/.claude/settings.json — keys reordered, "opus" turned into
# "opus[1m]" — even when settings.json already declares the marketplace and
# enables the plugin, which it does. That file is this repository's, so its
# bytes are saved first and written back through the symlink afterwards.
# `marketplace update` and `plugin update` do not write it.
SAVED="$(mktemp)"
cp "$CONF_DIR/settings.json" "$SAVED"
# Write the bytes back to the repository file, then relink: if a command
# replaced the symlink with a regular file, link() moves that file to the
# backup directory and points ~/.claude/settings.json at the repository again.
restore_settings() {
  cat "$SAVED" > "$CONF_DIR/settings.json"
  [ -L "$CLAUDE_HOME/settings.json" ] || link "$CONF_DIR/settings.json" settings.json
}

plugin_present() { claude plugin list 2>/dev/null | grep -qF "$1"; }

claude plugin marketplace list 2>/dev/null | grep -qw agent-config \
  || claude plugin marketplace add "$MARKETPLACE" >/dev/null || true

# morph is the core team. devops is a domain plugin: it is installed but stays
# off (defaultEnabled: false in the marketplace, false in settings.json) until
# it is switched on in /plugin.
for p in "$CORE" "$DOMAIN"; do
  if plugin_present "$p"; then
    log "$p present (updates arrive through the marketplace's autoUpdate)"
  elif claude plugin install "$p" >/dev/null; then
    log "installed $p"
  else
    log "install failed — run: claude plugin install $p"
  fi
done

# The old plugin's agents and skills would run beside morph's.
if plugin_present "$OLD"; then
  if claude plugin uninstall "$OLD" >/dev/null; then
    log "uninstalled $OLD (replaced by $CORE and $DOMAIN)"
  else
    log "could not uninstall $OLD — run: claude plugin uninstall $OLD"
  fi
fi

# The key goes in on stdin, never as an argument: an argument is visible to
# anyone who runs `ps`. A sensitive option is stored outside settings files.
if [ -n "${CONTEXT7_API_KEY:-}" ]; then
  jq -n --arg k "$CONTEXT7_API_KEY" '{context7_api_key: $k}' \
    | claude plugin configure "$CORE" --values-stdin >/dev/null \
    && log "context7 key set" || log "context7 key not set — run /plugin configure $CORE"
else
  log "no CONTEXT7_API_KEY in .env — context7 runs unauthenticated (lower rate limit)"
fi

restore_settings
rm -f "$SAVED"
PLUGIN_STATE="$(claude plugin list 2>/dev/null | grep -A4 -F "$CORE" || true)"
case "$PLUGIN_STATE" in
  *enabled*) log "$CORE enabled" ;;
  "")        log "WARNING: $CORE is not installed — agents and skills are missing" ;;
  *)         log "WARNING: $CORE is installed but not enabled — check /plugin" ;;
esac
log "$DOMAIN is installed but off. Switch it on in /plugin, or: claude plugin enable $DOMAIN"
log "(that changes one line, enabledPlugins, in claude/settings.json — commit it or leave it)"

# The plugins now provide context7 and aws-documentation. The user-scope copies
# earlier versions registered would run beside them (and an identical one hides
# the plugin's), so they go once the plugin is in place. Matched at line start:
# a plugin's own entry is listed as plugin:morph:context7.
INSTALLED=$(claude mcp list 2>/dev/null || true)
if plugin_present "$CORE"; then
  for n in context7 awslabs.aws-documentation-mcp-server; do
    if printf '%s\n' "$INSTALLED" | grep -q "^$n:"; then
      claude mcp remove "$n" --scope user >/dev/null && log "removed user-scope MCP $n"
    fi
  done
fi

# Agent memory lives in each repository's working tree, so it is not moved from
# here. Name the renames; run them in every repository that has the old paths.
log "in each repository with .claude/agent-memory-local/devops-core-*, rename:"
log "  devops-core-devops-implementer -> morph-implementer"
log "  devops-core-troubleshooter     -> morph-investigator"

step "Global gitignore"
# Claude Code drops machine-local files next to whatever repository it runs
# in. Ignoring them once here beats editing .gitignore in every work tree.
IGNORE="$(git config --global core.excludesFile 2>/dev/null || true)"
IGNORE="${IGNORE/#\~/$HOME}"
[ -n "$IGNORE" ] || IGNORE="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
mkdir -p "$(dirname "$IGNORE")"
# `**/` because a pattern with a slash in the middle is anchored to the
# repository root, and a session started in a subdirectory drops its own .claude/.
for pat in '**/.claude/settings.local.json' '**/.claude/agent-memory/' '**/.claude/agent-memory-local/' '**/.claude/.headroom_wrap_*' '**/.claude/claude-md-review.md'; do
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
# Routing goes through `headroom wrap claude`, run per session: it writes
# ANTHROPIC_BASE_URL and its selfheal hook to <repo>/.claude/settings.local.json,
# which is project-local and untracked. When the session ends it removes the
# routing and keeps the selfheal hook, which clears a dead proxy's address.
#
# `headroom init --global claude` is deliberately not run. It writes the same
# routing permanently into ~/.claude/settings.json, which is a symlink to this
# repo, so every install would dirty the tracked file with one machine's paths.
# There is no user-level settings.local.json to send it to instead: Claude Code
# reads that file only as the local settings of the project it was started in.
#
# `wrap` also registers headroom's MCP server in ~/.claude.json on every run,
# with the proxy's current port, so nothing here registers it.
command -v headroom  >/dev/null || uv tool install headroom-ai
command -v graphify  >/dev/null || { uv tool install graphifyy && graphify install --platform claude; }
log "start sessions with: headroom wrap claude    verify with: headroom doctor"

step "Done"
log "restart Claude Code to pick up hooks and env changes"
[ -d "$BACKUP_DIR" ] && log "files replaced on first install are in $BACKUP_DIR"
exit 0
