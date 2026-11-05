---
name: worktree
description: This repo's worktree bootstrap with bin/setup_worktree.sh and the DSH shared-checkout rule. Use alongside the global git-worktree skill when setting up or cleaning up a worktree for this app.
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
`flutter pub get`, and creates `dev_data/`. Project skills live in `.agents/skills/`, so
the script does not touch the catalog. Re-seed `dev_data/igc` only if the task needs the
app to actually run.

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

Background jobs and the interactive session often share this one checkout.

DSH has no guard. A background bash job or a subagent can run `git checkout`, `switch`, or
`reset` in the shared checkout without a prompt. The rule replaces the guard: run
ref-moving git commands in a worktree, not in the shared checkout.

The retired Claude Code guards (`worktree.bgIsolation` and the `PreToolUse` hook) and the
2026-08-04 branch-switch incident are in `docs/archive/claude-code/worktree.md`.
