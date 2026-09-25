# Proposing Learnings

Read this when Step 6 of `devops.md` has found something worth recording. It holds what qualifies, where the draft goes, and how to word it. The draft is always a proposal for the user to review — never a direct edit to `AGENTS.md` or `CLAUDE.md`.

## What qualifies

- Verified commands with their exact path/context; conventions and patterns confirmed this session; gotchas and how they were resolved; a short imperative rule whenever you or a subagent did something that should not happen again.
- **Record what someone could meet again, not what happened.** `AGENTS.md` says how the repository works now. "Fixed the ALB module's access logs" is an event and belongs in the pull request; "A module never configures a provider; it inherits the caller's" is how the place works and belongs here. An aphorism with no handle on it ("X is not always Y") is not a fact either — keep the concrete instance.
- **A false line costs more than a missing one.** Durable memory is trusted, so a wrong entry sends people down a path that does not exist. Read what the section already claims before appending, and prune a line when it stops being true — not when it gets old. Length is not the failure.

## Where the draft goes

Add a dated entry at the top of `.claude/claude-md-review.md` in the target repo — newest first, directly under the file's `#` title — creating the file with that title if it does not exist. Proposals sit in the review file until the user applies them.

The heading format is a contract, not a style: `## YYYY-MM-DD — short title`. A `SessionStart` hook counts headings that do not carry the word `APPLIED` and raises them in the next session in this repository. Write a heading in any other shape and that count silently reads zero — the proposal is then in the file and reminds nobody. When the user applies an entry, append ` — APPLIED` to its heading rather than deleting it.

Fold in the implementer's returned Learnings and the troubleshooter's, plus your own review findings, into the same dated entry. Check the file's existing unreviewed proposals first — merge with a matching one rather than duplicating it, and note when a new proposal supersedes an older pending one.

## How to word it

Bullets taken from repositories here:

```
A module never configures a provider; it inherits the caller's. Its own provider
block would make count and for_each unusable on the module and would quietly
override the region and default tags the live layer set.

Do not create CHANGELOG.md for every new module — release-please creates and
maintains that file.

Examples and defaults use `dummy` rather than a real client or account name.
```

The first carries a consequence because the rule is not self-evident. The second names what owns the file, so nobody re-litigates it. The third is short because it needs nothing more. None of them record an event.

- English, one line per bullet, never a paragraph. The review file is a staging area for text pasted verbatim into the target file, so it must already read like the target file.
- For each proposed change, write the exact bullet(s) to add, edit, or remove, targeted at `AGENTS.md`'s `## DevOps Conventions (agent-maintained)` section (creating that section if missing when the user applies it).
- Claude Code loads `CLAUDE.md`, not `AGENTS.md`, so where the repo's `CLAUDE.md` lacks an `@AGENTS.md` import at the top, say that it needs one.
