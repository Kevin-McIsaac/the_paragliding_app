# Claude Code Bash sandbox (retired)

This page records the sandbox settings the repo used under Claude Code. DSH does not read
them. The current recovery steps are in the `sandbox-setup` skill.

## Settings

Claude Code's sandbox was set up per developer in `~/.claude/settings.json`. Three entries
mattered for this project.

### `sandbox.excludedCommands`

`bin/dev_*.sh`, `adb`, and `flutter devices` ran outside the sandbox. A sandboxed shell had
no X11 display and no network interface beyond `lo`, so a desktop launch failed with
`Gtk-WARNING cannot open display: :0`, adb over Wi-Fi failed with "Network is unreachable",
and `flutter devices` listed only Linux and Chrome.

### `filesystem.allowWrite`

Android builds needed three paths beyond the standard Flutter paths:

- `/tmp` - Gradle's `mergeDebugJavaResource` writes through Java's `java.io.tmpdir`, which
  ignores `TMPDIR`.
- `~/.local/share/kotlin` - the Kotlin compile daemon.
- `~/.config/.android` - the debug keystore. Not `~/.android`, which is a different path.

### `network.strictAllowlist`

With the allowlist on, a missing host was a hard failure. Gradle needed `dl.google.com`,
`maven.google.com`, `repo.maven.apache.org`, `repo1.maven.org`, `services.gradle.org`, and
`plugins.gradle.org`. Network-tagged tests needed `storage.openaip.net`.

## Claude-only commands

- `/sandbox` managed the allowlist.
- `dangerouslyDisableSandbox: true` ran a command outside the sandbox.
- A background job set `CLAUDE_JOB_DIR`. The shared-checkout hook used it.

## Why the sandbox read as a headless machine

The sandbox hid the X11 socket and the LAN. Both failures looked like a missing display or
a missing phone. The machine had a display. Do not look for `Xvfb`.
