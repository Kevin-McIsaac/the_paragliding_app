---
name: worktree
description: This repo's worktree specifics - bootstrapping a fresh worktree with bin/setup_worktree.sh (env.json and android/key.properties fail silently if skipped), and the shared-checkout isolation guards (worktree.bgIsolation and guard-shared-checkout.sh). Use alongside the global git-worktree skill when setting up, or cleaning up, a worktree for this app.
---

# Worktrees in this repo

The **portable mechanics** - creating one from `origin/main`, the merge sequence, `-D` after a
squash merge, and proving a merge landed - live in the global **`git-worktree`** skill. Load
it for those. This file is only what is specific to this repo.

Worktrees live in `.claude/worktrees/` (gitignored), branched from `origin/main`, and are
removed once the work merges.

## Bootstrap: `bin/setup_worktree.sh`

A fresh worktree has none of the gitignored files. Run the script from inside the new
worktree:

```bash
bin/setup_worktree.sh
```

It copies `env.json` and `android/key.properties` from the main checkout, runs
`flutter pub get`, creates `dev_data/`, and rebuilds the `.dsh/skills/` symlink bridge -
without which every project skill disappears from the session catalog inside a worktree.
Re-seed `dev_data/igc` only if the task needs the app to actually run.

The two file copies fail **silently**, which is why the script exists:

- **`env.json` missing** - everything builds and runs, but FFVL weather, OpenAIP overlays
  and Cesium 3D are silently unconfigured. `bin/dev_run.sh` warns; a bare `flutter run`
  does not. Confirm with the `[API_KEYS_STATUS]` line at startup.
- **`android/key.properties` missing** - `flutter build appbundle --release` **succeeds**
  and signs with the *debug* key. `android/app/build.gradle.kts` falls back deliberately
  and only `println`s a warning, which is invisible in normal build output. Play rejects
  the upload. Always verify before uploading:

  ```bash
  keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | grep -E "Owner:|SHA256:"
  ```

  Expect `Owner: CN=Kevin McIsaac, ...`. `CN=Android Debug` means the fallback fired. The
  fingerprint must match `upload-cert-new.pem`:
  `openssl x509 -in ../upload-cert-new.pem -noout -fingerprint -sha256`.

## Why isolation here: several sessions share one checkout

Background jobs, plus whatever you have open interactively, often share this one checkout.
Two guards keep them off each other:

- `worktree.bgIsolation: "worktree"` (`.claude/settings.json`) blocks Edit/Write in the
  shared checkout from a background session until it calls EnterWorktree.
- `.claude/hooks/guard-shared-checkout.sh` covers what that misses. bgIsolation does not
  gate **Bash**, and on 2026-08-04 a background job that was correctly isolated for its
  edits still ran `git checkout`/`reset` against the shared checkout, switching the branch
  out from under another session mid-rebase. The hook asks before a background session runs
  a ref-moving git command outside a worktree. Interactive sessions are never gated, and
  read-only git (`status`/`log`/`diff`/`fetch`) passes untouched.

If you see that prompt, the honest question is whether the command belongs in a worktree
instead. Approving is fine when you asked for it.
