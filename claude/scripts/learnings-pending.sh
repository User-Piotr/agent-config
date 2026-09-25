#!/usr/bin/env bash
# ~/.claude/scripts/learnings-pending.sh
#
# SessionStart hook. Reports unapplied learnings proposals left by earlier
# sessions in this repository.
#
# SessionStart is one of the four events whose stdout Claude Code adds to the
# model's context (the others are UserPromptSubmit, UserPromptExpansion and
# PostModelSwitch). That is the whole reason review happens at the start of a
# session rather than at the end of the previous one: at SessionEnd there is
# nowhere to put the text.
set -uo pipefail

[[ -n "${CLAUDE_LEARNINGS_CHILD:-}" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
CWD="$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)"

REPO="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"
[[ -n "$REPO" ]] || exit 0

REVIEW="$REPO/.claude/claude-md-review.md"
[[ -f "$REVIEW" ]] || exit 0

# Entry headings look like `## 2026-09-12 — title`; applied ones carry APPLIED.
# Count only DATED headings: a file titled `## Proposed learnings` would
# otherwise read as one pending entry forever, a reminder nobody can clear.
PENDING="$(grep -E '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$REVIEW" 2>/dev/null | grep -vc 'APPLIED')" || PENDING=0
[[ "$PENDING" -gt 0 ]] || exit 0

printf '%s unapplied learnings proposal(s) sit in .claude/claude-md-review.md, queued by earlier sessions in this repository. Nothing there is in effect until a human moves it into AGENTS.md. Raise them when the current task reaches a natural pause — summarise each in a line and ask whether to apply, edit, or drop it. Do not apply them unprompted. Compare each against what AGENTS.md says now: an entry whose content is already there was applied and never marked, so offer to append " — APPLIED" to its heading instead of raising it again next session.\n' "$PENDING"
exit 0
