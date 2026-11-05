---
name: sandbox-setup
description: Recover from DSH sandbox denials for Flutter, adb, and Gradle. Use when a command fails with "cannot open display", "Read-only file system", or a sandbox denial.
---

# Sandbox recovery

DSH runs Bash under `workspace-write`. The sandbox gives a read-only host root, a writable
workspace, an ephemeral `/tmp`, a private PID namespace, and an unrestricted network.

Claude Code is retired. Its sandbox settings are archived at
`docs/archive/claude-code/sandbox.md`.

## Escalation

A denied operation returns `[sandbox: file access denied under workspace-write mode]`.
Retry the exact command once with `sandbox_permissions` set to the narrowest wider mode
(usually `danger-full-access`) and a one-sentence justification. That retry raises the
approval prompt. Do not set `danger-full-access` as the default.

## Display

The X11 socket is hidden. The Wayland socket at `/run/user/1000/wayland-0` is not. There is
a display. Do not look for `xvfb`.

## Flutter

`~/flutter` is outside the workspace. A sandboxed `flutter` can fail at
`bin/cache/engine.stamp: Read-only file system` before GTK code runs. Run the `flutter-dev`
export first. If it still fails, escalate once.

## Working directory

A sandboxed build works in the session's working directory. Building in a different
checkout fails at `.dart_tool/package_graph.json` with `Read-only file system`. Run from
the repo or the app directory.

## PID visibility

The sandbox has a private PID namespace. A healthy app's pid is invisible inside it, so
`kill -0` fails as it would for a dead app. Check `dev_data/flutter.log` before you declare
the app dead.

## `could not lock config file .git/config: File exists`

A config write can fail after the real operation succeeded. Check the result before you
retry. Use `git push origin HEAD` instead of `git push -u`. Verify with
`git ls-remote --heads origin <branch>` or `git worktree list`.

## adb and the LAN

The DSH sandbox does not block the LAN. `adb mdns services`, `adb pair`, `adb connect`,
`adb devices -l`, and `flutter devices` work with `workspace-write` on. Try a sandboxed
call before escalating.
