#!/usr/bin/env bash
# Install agent tool configurations. Each tool is a directory with its own
# install.sh; pass names to install a subset.
#
#   ./install.sh            # every tool
#   ./install.sh claude     # just one
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Shared secrets, exported so every tool installer inherits them.
if [ -f "$REPO_DIR/.env" ]; then
  set -a; . "$REPO_DIR/.env"; set +a
else
  echo "no .env — copy .env.example and fill it in, or keyed servers get skipped"
fi

TOOLS=("$@")
[ "${#TOOLS[@]}" -gt 0 ] || TOOLS=(claude)   # add new tool directories here

for tool in "${TOOLS[@]}"; do
  printf '\n=== %s ===\n' "$tool"
  bash "$REPO_DIR/$tool/install.sh"
done
