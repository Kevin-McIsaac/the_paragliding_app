#!/usr/bin/env bash
#
# PreToolUse(Bash) guard: stop a BACKGROUND session from moving branch state in the
# SHARED checkout while another session is working there.
#
# Why this exists, and why worktree.bgIsolation is not enough on its own:
# bgIsolation blocks Edit/Write in the main checkout until a background job calls
# EnterWorktree - but it does not gate Bash. On 2026-08-04 a background job that was
# correctly isolated for its *edits* still ran git checkout/reset against the shared
# checkout, switching the branch out from under another session mid-rebase. Nothing
# was lost that time; nothing prevented it either.
#
# Scope, deliberately narrow:
#   - interactive sessions are never gated - they own the checkout
#   - a session already inside .claude/worktrees/ is never gated - that is the point
#   - only commands that MOVE HEAD or rewrite refs are gated; read-only git
#     (status/log/diff/show/fetch) passes untouched
#
# It asks rather than denies. A background job sometimes genuinely should pull or
# check out in the shared checkout - when the user just told it to. Asking makes that
# a decision instead of a silent collision.

set -euo pipefail

payload="$(cat)"
cmd="$(jq -r '.tool_input.command // ""' <<<"$payload" 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0

# Only background sessions are gated. CLAUDE_JOB_DIR is set for background jobs.
[[ -n "${CLAUDE_JOB_DIR:-}" ]] || exit 0

# Already isolated: nothing to protect.
case "$PWD" in
  */.claude/worktrees/*) exit 0 ;;
esac

# Ref-moving subcommands. Anchored to a `git` word so `git log --grep=reset` and
# paths like ./scripts/reset.sh do not trip it.
if ! grep -qE '(^|[;&|(]|&&|\|\|)[[:space:]]*git[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(checkout|switch|reset|rebase|merge|pull|cherry-pick|stash|branch[[:space:]]+-[Dd])\b' <<<"$cmd"; then
  exit 0
fi

reason="This is a background session working in the SHARED checkout ($PWD), not a worktree.
Other Claude sessions and the user may be on this same checkout right now, and this
command moves HEAD or rewrites refs - that is how a branch gets switched out from
under someone else's rebase.

If the user asked for this, approve it. Otherwise prefer EnterWorktree first."

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $r
  }
}'
