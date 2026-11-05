# Claude Code archive

This repo used Claude Code until 2026-11. DSH (DeepSeek Harness) is the current harness.

## Active under DSH

- `.agents/skills/` - project skills. DSH scans this directory directly.
- `.agents/skills/flutter-log-analyzer/agent.md` - the agent definition.
- `.claude/worktrees/` - worktree path used by the `git-worktree` skill.

## Inactive, kept in place

- `.claude/settings.json` - permissions, `worktree.bgIsolation`, and the `PreToolUse` hook.
- `.claude/hooks/guard-shared-checkout.sh` - Claude Code hook.
- `.claude/statusline.sh` - wired in the global `~/.claude/settings.json`.

No current harness reads these files. They stay for a future restore.

## Removed

- `CLAUDE.md` - `AGENTS.md` is the only rules file.
- `.claude/skills/` - moved to `.agents/skills/`.

## Extracted notes

- [ci-review.md](ci-review.md) - the retired Claude Code PR review workflow.
- [sandbox.md](sandbox.md) - Claude Code Bash sandbox settings.
- [worktree.md](worktree.md) - `bgIsolation` and the shared-checkout hook.
- [run-app.md](run-app.md) - Claude Code sandbox notes for running the app.

## Restore

1. Restore `.claude/skills/` from git history.
2. Re-create `CLAUDE.md` as a symlink to `AGENTS.md`.
3. Re-enable `.claude/settings.json`, the hook, and the statusline.
4. Read the extracted notes on this page.
