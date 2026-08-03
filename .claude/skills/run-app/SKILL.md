---
name: run-app
description: Run, hot-reload, screenshot and read logs for this Flutter app, on Linux desktop or on an Android phone/emulator. Use when asked to run, launch, start, restart or hot-reload the app, to screenshot it, to check its runtime logs, or to verify a change in the running app rather than in tests. Covers bin/dev_run.sh, bin/dev_reload.sh, wireless adb device ids, and the debug-vs-production package trap.
---

# Running this app

All commands run from the **repo root**. `bin/dev_run.sh` `cd`s into `the_paragliding_app/`
itself, so there is no working-directory trap.

## 1. Pick a target

**Linux desktop is the default** and needs no device. Use it unless the task needs a phone.

Android is required for 3D map work only: `flutter_inappwebview` has no Linux
implementation, so 3D screens show a "3D Map Not Available" placeholder on desktop.

## 2. Start it

```bash
bin/dev_run.sh --background                 # desktop
bin/dev_run.sh -d "<device>" --background   # Android
```

`--background` detaches the app and returns **only once it is actually up** — or fails
fast with the real error and the tail of the log. Agents should always use it; without it
the command blocks until you quit the app.

Get `<device>` from `flutter devices` (not `adb devices` — Flutter wants its own id). The
wireless Pixel 9 looks like `adb-52110DLAQ001UT-hkZkFs._adb-tls-connect._tcp`. **Always
quote it.**

Other flags: `--profile` (real timings, no hot reload), `--reset` (desktop only, wipes
`dev_data/app_documents` and re-seeds).

## 3. Change code, then reload

```bash
bin/dev_reload.sh      # hot reload
bin/dev_reload.sh R    # hot restart - needed after main()/initState changes
```

Works from anywhere, including when the app was started detached. Confirm it landed —
`Reloaded N libraries in Xms` or `Restarted application in Xms` appears in the log. Do not
assume; a reload that goes nowhere looks exactly like one that worked.

## 4. Look at what happened

```bash
tail -n 50 dev_data/flutter.log                  # recent output
grep -E "\[[IWEDP]\]\[\+" dev_data/flutter.log   # just this app's LoggingService lines
adb -s "$DEV" exec-out screencap -p > dev_data/screenshot.png   # then Read the PNG
```

Use `exec-out`, not `shell` — `shell` mangles the binary. Pass `-s "$DEV"`; there is
usually more than one thing attached.

To be told about problems as they happen instead of grepping after the fact, watch the
log with the `Monitor` tool rather than polling it:

```bash
tail -f dev_data/flutter.log | grep --line-buffered -E "EXCEPTION CAUGHT|overflowed|\[E\]\[|Lost connection"
```

`--line-buffered` is required or matches sit in grep's buffer unseen. Widen the pattern
rather than narrowing it — a filter that only matches success stays silent through a
crash, and silence looks exactly like "still running".

## 5. Stop it

```bash
kill "$(cat dev_data/flutter.pid)"          # stop
kill -0 "$(cat dev_data/flutter.pid)"       # still running?
```

Flutter writes `dev_data/flutter.pid` only once the app is up and removes it on exit, so
that file **is** the readiness check. There is no status command and none is needed.

## Traps

- **Two packages are installed on the phone.** Debug is `com.theparaglidingapp.debug`
  ("Paragliding App (debug)"); production is `com.theparaglidingapp` and holds the user's
  **real flight log, which exists nowhere else**. Never `pm clear`, `pm uninstall`, or
  Clear Data on the unsuffixed one. Check which you are looking at — `adb shell ps -A |
  grep theparaglidingapp` prints the package per pid, and screenshots of the two are
  indistinguishable. The `.debug` suffix exists because without it the debug keystore
  clashes with the release signature (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`) and Flutter
  silently uninstalls the production app, taking its database with it.
- **`--reset` is desktop-only** and refuses on a device target rather than pretending to
  work. To clear the debug app on device, run `adb -s "$DEV" shell pm clear
  com.theparaglidingapp.debug` deliberately — and never without the suffix.
- **No dev seeding on Android.** `dev_data/igc` fixtures are host paths; the phone shows
  whatever data is already installed there.
- **Verify the artifact, not the status.** "Started OK" means nothing on its own — read
  `dev_data/flutter.log` or look at a screenshot. The deleted `flutter_controller_enhanced`
  reported `Running / Pipe Responsive` for a process that had already exited, and set
  `ERROR` by string-matching Flutter's own help text. See "Verifying work" in CLAUDE.md.
- **A screenshot of a locked phone is the lock screen**, and it looks like a plausible
  capture (valid PNG, right dimensions). Unlock before capturing.
- **Missing `env.json` fails silently** — FFVL weather, OpenAIP overlays and Cesium 3D go
  unconfigured with no error. Confirm the `[API_KEYS_STATUS]` line at startup.
- **One log per checkout**, truncated on each run. Worktrees each get their own.
- **Do not drive the app's UI with adb taps.** Ask the user to navigate.

## Wireless debugging (physical device)

```bash
# On the phone: Settings > System > Developer options > Wireless debugging
adb pair <ip>:<pairing-port> <6-digit-code>   # "Pair device with pairing code" dialog
adb connect <ip>:<connect-port>               # DIFFERENT port, on the main screen
flutter devices                               # confirm, then use the id with -d
```

The pairing port and the connect port are different — mixing them up is the usual failure.
Pairing is permanent; re-run only `adb connect` in later sessions. A stale pairing dialog
leaves its port listening but dead, which surfaces as `error: protocol fault (couldn't read
status message)` — reopen the dialog for a fresh port and code. `adb mdns services` returns
nothing from a Crostini container (multicast does not cross the NAT), so always use an
explicit `IP:port`.
