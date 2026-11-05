# Claude Code notes for running the app (retired)

This page records the Claude Code sandbox notes removed from the `run-app` skill. DSH does
not read them.

## Run every `bin/dev_run.sh` with the sandbox disabled

Under Claude Code, `bin/dev_run.sh` ran with `dangerouslyDisableSandbox: true`. The rule
covered `bin/dev_reload.sh`, `bin/dev_logs.sh`, `bin/dev_screenshot.sh`, and every `adb`
command. The sandbox reached neither the X11 socket nor the phone's LAN address. Both
failures read as a missing display or a missing phone.

| you see | it is | do |
|---|---|---|
| `cannot open display: :0` | the sandbox, hiding X11 | re-run with the sandbox off |
| `Network is unreachable` | the sandbox, hiding the LAN | re-run with the sandbox off |
| `flutter pid N is not visible` | the sandbox's own PID namespace | re-run with the sandbox off |
| `No route to host` | genuinely the network | phone asleep or off Wi-Fi |

The sandbox ran in its own PID namespace. A healthy app's pid was invisible inside it, so
`kill -0` failed as it would for a dead app. Check `dev_data/flutter.log` before declaring
the app dead.

`/sandbox` managed the allowlist.

## adb over the LAN

The Claude Code network allowlist covered pub.dev, GitHub, and the app's APIs, but not the
phone's LAN address. Anything that reached the phone over Wi-Fi failed with:

```
failed to connect to '192.168.86.99:5555': Network is unreachable
```

Re-run with the sandbox disabled. That included `bin/dev_run.sh -d "<device>"`, which
talks to the phone through the build-install-attach cycle.
