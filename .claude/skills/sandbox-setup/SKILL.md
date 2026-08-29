---
name: sandbox-setup
description: Configure this project's requirements into a developer's personal Claude Code Bash sandbox (~/.claude/settings.json) - excludedCommands, filesystem.allowWrite, and network.strictAllowlist entries. Use when a sandboxed command fails with "cannot open display", "Network is unreachable", "Read-only file system", or a blocked host during a Flutter/Gradle/adb command, or when setting up a new machine for this repo.
---

# This project's Bash-sandbox requirements

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

## Deeper reference

The general mechanics of this sandbox (why it's still worth keeping under auto mode,
`strictAllowlist` vs plain `allowedDomains`, the PID-namespace and phantom-dotfile
quirks, how to revert) live in the user's own cross-project memory, not here - this
skill only tracks what *this repo's* build and run scripts specifically need.
