# Claude Code shared-checkout guards (retired)

This page records the two guards the repo used under Claude Code. DSH does not run them.
The current rule is in the `worktree` skill.

## `worktree.bgIsolation: "worktree"`

`.claude/settings.json` blocked Edit/Write in the shared checkout from a background
session until it called `EnterWorktree`. It did not gate **Bash**.

## `PreToolUse` hook

`.claude/hooks/guard-shared-checkout.sh` asked before a background session ran a
ref-moving git command outside a worktree. It read `CLAUDE_JOB_DIR` from the payload and
exited when the variable was absent. Interactive sessions were never gated. Read-only git
(`status`, `log`, `diff`, `fetch`) passed untouched.

## The incident behind the hook

On 2026-08-04, a background job that was correctly isolated for its edits still ran
`git checkout` and `reset` against the shared checkout. It switched the branch out from
under another session mid-rebase. Nothing was lost. Nothing prevented it either.

## Restore

Restore `.claude/settings.json` and `.claude/hooks/guard-shared-checkout.sh` from git
history. Check that the hook is executable and that the settings file points at it.
