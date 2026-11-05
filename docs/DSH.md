# Run this repo under DSH

DSH (DeepSeek Harness) is the current harness. This page lists the project files it
reads, the settings it needs, and the few Claude Code features that do not carry over.

The retired Claude Code setup is archived at
[docs/archive/claude-code/README.md](archive/claude-code/README.md).

## Project skills

Project skills live in `.agents/skills/`. DSH scans that directory directly, so a fresh
clone needs no setup command.

`bin/setup_worktree.sh` bootstraps a new worktree. It copies `env.json` and
`android/key.properties` from the main checkout and runs `flutter pub get`. In the main
checkout it prints a message and exits.

## What DSH reads

| File | Behavior |
|---|---|
| `AGENTS.md` | Project instructions. |
| `.agents/skills/*` | Skill catalog. Load one with the `skill` tool. |
| `.claude/agents/flutter-log-analyzer.md` | Read through the `flutter-log-analyzer` skill. |
| `~/.dsh/skills` | Global skills (dotfiles). The project skills refer to `flutter-dev`, `git-worktree`, and `verification`. |
| `.claude/worktrees/` | Worktree path used by the `git-worktree` skill. |
| `bin/setup_worktree.sh` | Worktree bootstrap. |

## What does not carry over

| Claude Code feature | DSH behavior |
|---|---|
| `.claude/skills/` | Moved to `.agents/skills/`. |
| `.claude/agents/*.md` | Not discovered. The `flutter-log-analyzer` skill points at the file. |
| `worktree.bgIsolation` | Claude-only. |
| `.claude/hooks/*` | Claude `PreToolUse` hooks do not run. |
| Permission allowlist | No equivalent. DSH approvals are one-shot and carry no command arguments. |
| `EnterWorktree`, `statusline.sh`, `outputStyle` | No equivalent. |

## Permissions

DSH uses a sandbox mode plus an approval policy. An operation that needs wider file access
is denied first. Retry it once with `sandbox_permissions` and a justification. That retry
raises the approval prompt. DSH has no allow-always rule, so each escalation asks again.

The `sandbox-setup` project skill explains the sandbox limits. It applies under DSH.

## CI

The Claude Code review job is retired. Its workflow is archived at
`docs/archive/claude-code/ci-review.md`.

The current review is `.github/workflows/pr-review.yml`. It is advisory and
provider-agnostic. See [PR Review](PR_REVIEW.md). It skips until `REVIEW_API_URL`,
`REVIEW_MODEL`, and an API key are set.

## Troubleshooting

- A project skill is missing: check that `.agents/skills/<name>/SKILL.md` exists.
- The log analyzer is missing: load the `flutter-log-analyzer` skill. It names the agent
  file to read.
- A background job moved the branch: DSH has no guard. Run ref-moving git commands in a
  worktree.
- The desktop app cannot open a display: the DSH sandbox hides the X11 socket but not the
  Wayland socket. See `sandbox-setup`. Do not set `danger-full-access` as the default.
