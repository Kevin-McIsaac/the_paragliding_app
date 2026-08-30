---
name: sandbox-setup
description: Configure this project's requirements into a developer's personal Claude Code Bash sandbox (~/.claude/settings.json) - excludedCommands, filesystem.allowWrite, and network.strictAllowlist entries. Use when a sandboxed command fails with "cannot open display", "Network is unreachable", "Read-only file system", or a blocked host during a Flutter/Gradle/adb command, or when setting up a new machine for this repo.
---

# This project's Bash-sandbox requirements

> **Agent environment matters.** Everything below was written for **Claude Code's** Bash
> sandbox, which has `excludedCommands`, `filesystem.allowWrite`, and a network
> allowlist. **Under DSH (DeepSeek Harness) none of those knobs exist** — its bwrap
> profile is fixed (read-only host root, writable workspace, ephemeral `/tmp`, private
> PID namespace, network unrestricted). Verified 2026-08-30 on this machine:
>
> - The **X11 socket is hidden** (`/tmp/.X11-unix` vanishes under the sandbox's tmpfs
>   overlay), but the **Wayland socket is not** — `/run/user/1000/wayland-0` connects
>   from inside. The "no display at all" framing is stale.
> - The first blocker for Flutter is not the display at all: `~/flutter` sits outside the
>   workspace, so a sandboxed `flutter` dies at
>   `bin/cache/engine.stamp: Read-only file system` before any GTK code runs.
> - The idiomatic DSH fix is the **per-command escalation flow**: a denied command is
>   retried once with `sandbox_permissions` (narrowest wider mode that suffices — usually
>   `danger-full-access`) plus a one-sentence justification, which raises an approval
>   prompt. Do not set `danger-full-access` as the default mode; it is unconfined, not a
>   wider profile. The Claude Code settings below are kept for reference on that host.

Claude Code's Bash sandbox is set up per-developer in `~/.claude/settings.json`, so
nothing in this repo turns it on and none of this shows up in a diff. If yours is
enabled, three things about *this* project need configuration that is not obvious. Each
was found by a failed run.

## excludedCommands

`bin/dev_*.sh`, `adb`, and `flutter devices` belong in `sandbox.excludedCommands`. A
sandboxed shell gets no X11 display and no network interface at all (`ip addr` shows
only `lo`), so a desktop launch dies with `Gtk-WARNING cannot open display: :0`,
adb-over-Wi-Fi fails with "Network is unreachable", and `flutter devices` lists only
Linux and Chrome. Those commands have to run outside the sandbox. It reads exactly like
a headless machine and is not one - that misdiagnosis once led to hunting for `Xvfb`.

## filesystem.allowWrite

Android builds need three extra paths beyond the standard Flutter ones
(`~/flutter`, `~/.pub-cache`, `~/.gradle`, `~/.dart`, `~/.config/flutter`, `~/.android`):

- `/tmp` - Gradle's `mergeDebugJavaResource` writes via Java's `java.io.tmpdir`, which
  is hardcoded to `/tmp` and **ignores `TMPDIR`**.
- `~/.local/share/kotlin` - the Kotlin compile daemon.
- `~/.config/.android` - the debug keystore. **Not** `~/.android`, which is a different
  path and already covered above.

## network.strictAllowlist

With it on, every missing host is a hard failure. Gradle needs `dl.google.com`,
`maven.google.com`, `repo.maven.apache.org`, `repo1.maven.org`, `services.gradle.org`
and `plugins.gradle.org` (`android/build.gradle.kts` declares `google()` and
`mavenCentral()`); `flutter test --tags network` needs `storage.openaip.net`.

## Working-directory trap

A sandboxed build only works in the session's own working directory. Building in a
*different* checkout fails early at `Cannot open file, path =
'.dart_tool/package_graph.json' (OS Error: Read-only file system)` - that is a
wrong-directory error, not a missing permission.

## `could not lock config file .git/config: File exists`

**The operation already succeeded. Only the config side-effect failed.** Check before you
retry — this exits non-zero after doing the work, so it reads as a failure and is not one.

The sandbox binds `/dev/null` over `.git/config.lock`:

```
.git/config       -rw-r--r--  kmcisaac        <- real file, writable
.git/config.lock  crw-rw-rw-  nobody  1, 3    <- /dev/null bind
```

Git writes config atomically — create `config.lock`, write, rename over `config` — so a
pre-occupied lock path makes every config write fail with `File exists`. `.git/config`
itself is writable, which is why adding it to `filesystem.allowWrite` does **not** help.

Only `config.lock` is masked. `index.lock`, `HEAD.lock` and friends are not, which is why
`git add` and `git commit` work normally and only config writes break. Affected:

| command | what still worked | what failed |
|---|---|---|
| `git push -u origin <branch>` | the push - the branch is on the remote | recording the upstream |
| `git worktree add -b <b> <path> origin/main` | nothing - it aborts | the tracking config, and it leaves an orphan branch |
| `git config`, `git remote add`, `git branch --set-upstream-to` | — | the whole command |

**Avoid it rather than configure around it:** `git push origin HEAD` instead of
`git push -u`. You lose upstream tracking, which costs nothing when the branch is named
explicitly. For `git worktree add`, drop `origin/main` and set the branch afterwards, or
run that one command with the sandbox disabled.

Verify the truth with `git ls-remote --heads origin <branch>` (for a push) or
`git worktree list` — never from the exit code.

## Deeper reference

The general mechanics of this sandbox (why it's still worth keeping under auto mode,
`strictAllowlist` vs plain `allowedDomains`, the PID-namespace and phantom-dotfile
quirks, how to revert) live in the user's own cross-project memory, not here - this
skill only tracks what *this repo's* build and run scripts specifically need.
