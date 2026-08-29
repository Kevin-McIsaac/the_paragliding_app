---
name: worktree
description: Create, bootstrap, and clean up a git worktree for feature/bugfix work on this app, and merge its PR back. Use when asked to start a new task/branch, set up a worktree, merge or clean up a PR from a worktree, or when hitting a "Removing will discard this work permanently" prompt. Covers bin/setup_worktree.sh, the shared-checkout isolation guards, the gitignored-file bootstrap trap, and why -D (not -d) is correct after a squash merge.
---

# Worktrees

Do feature and bugfix work in a git worktree, one per task, branched from `origin/main`.
They live in `.claude/worktrees/` (gitignored) and are removed once the work merges.

## Why: several sessions share one checkout

Background jobs, plus whatever you have open interactively, often share this one
checkout. Two guards keep them off each other:

- `worktree.bgIsolation: "worktree"` (`.claude/settings.json`) blocks Edit/Write in the
  shared checkout from a background session until it calls EnterWorktree.
- `.claude/hooks/guard-shared-checkout.sh` covers what that misses. bgIsolation does not
  gate **Bash**, and on 2026-08-04 a background job that was correctly isolated for its
  edits still ran `git checkout`/`reset` against the shared checkout, switching the
  branch out from under another session mid-rebase. The hook asks before a background
  session runs a ref-moving git command outside a worktree. Interactive sessions are
  never gated, and read-only git (`status`/`log`/`diff`/`fetch`) passes untouched.

If you see that prompt, the honest question is whether the command belongs in a worktree
instead. Approving is fine when you asked for it.

## Bootstrapping a fresh worktree

A fresh worktree has none of the gitignored files - `env.json`, `android/key.properties`,
`.dart_tool/`, `build/`, `dev_data/`. `env.json` and `key.properties` fail silently
rather than loudly if skipped, and the signing one is dangerous:

- **`env.json` missing** - everything builds and runs, but FFVL weather, OpenAIP
  overlays and Cesium 3D are silently unconfigured. `bin/dev_run.sh` warns; a bare
  `flutter run` does not. Confirm with the `[API_KEYS_STATUS]` line at startup.
- **`android/key.properties` missing** - `flutter build appbundle --release` **succeeds**
  and signs with the *debug* key. `android/app/build.gradle.kts` falls back deliberately
  and only `println`s a warning, which is invisible in normal build output. Play rejects
  the upload. Always verify before uploading:

  ```bash
  keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | grep -E "Owner:|SHA256:"
  ```

  Expect `Owner: CN=Kevin McIsaac, ...`. `CN=Android Debug` means the fallback fired.
  The fingerprint must match `upload-cert-new.pem`:
  `openssl x509 -in ../upload-cert-new.pem -noout -fingerprint -sha256`

Run `bin/setup_worktree.sh` from inside the new worktree to handle both copies plus
`flutter pub get` and `mkdir -p dev_data` in one step, instead of doing it by hand:

```bash
bin/setup_worktree.sh
```

Re-seed `dev_data/igc` only if the task needs the app to actually run.

## Merging: `gh pr merge <n> --squash`, without `-d`

The repo has *Automatically delete head branches* enabled, so GitHub removes the branch
server-side and `gh` runs no local git at all. Passing `-d` asks gh to delete the
**local** branch too, which makes it run `git checkout main` - and that fails from a
worktree, because `main` is checked out in the shared checkout. It fails *after* the API
merge has already gone through, so the PR is merged while the command exits 1: check
`gh pr view <n> --json state` before assuming it did not land. Clean up locally instead:

```bash
git worktree remove .claude/worktrees/<name>
git branch -D <name>               # -D, not -d: see below
git fetch --prune origin
git merge --ff-only origin/main    # from the shared checkout
```

`-D` is not carelessness. A squash merge rewrites the work into a single new commit, so
the branch's own commits are never ancestors of `main` and `git branch -d` refuses it as
"not fully merged" - which is true of the commits and false of the content. Confirm the
content landed by checking the PR is `MERGED`, not by whether `-d` is willing.

**The EnterWorktree/ExitWorktree tooling asks that same question**, and refuses to
remove a merged worktree - "Removing will discard this work permanently" - until told
`discard_changes: true`. It is the same false negative rather than a second problem; it
fired on 2026-08-15 for the already-merged `network.yml` branch. Answer it the same way,
and prove the content landed by comparing trees instead of trusting either tool:

```bash
gh pr view <n> --json state                       # MERGED is the authority
git diff --stat <branch> origin/main -- <paths>   # empty output means nothing is lost
```

Changing merge strategy does not avoid this, and **rebase merge especially does not** -
GitHub re-parents each commit onto `main`, so the SHAs change and ancestry breaks exactly
as it does under squash. Only a real merge commit preserves it, at the cost of the squash
body, which is where the PR description on most of these commits comes from. Running
`git reset --hard origin/main` in the worktree first silences both prompts, but it
discards the local commit for real - on a branch that did *not* merge that destroys the
work, which is precisely the case the prompt exists to catch. Confirm the prompt instead.
