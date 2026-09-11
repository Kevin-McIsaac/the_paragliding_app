---
name: run-app
description: Run, hot-reload, screenshot and read logs for this Flutter app, on Linux desktop or on an Android phone/emulator. Use when asked to run, launch, start, restart or hot-reload the app, to screenshot it, to check its runtime logs, or to verify a change in the running app rather than in tests. Also use when asked to tap, scroll, drag or otherwise drive the app's UI to reach a screen. Covers bin/dev_run.sh, bin/dev_reload.sh, bin/dev_screenshot.sh, bin/dev_input.sh, wireless adb device ids, and the debug-vs-production package trap.
---

# Running this app

All commands run from the **repo root**. `bin/dev_run.sh` `cd`s into `the_paragliding_app/`
itself, so there is no working-directory trap.

## 1. Pick a target

**Linux desktop is the default** and needs no device. Use it unless the task needs a phone.

Android is required for 3D map work only: `flutter_inappwebview` has no Linux
implementation, so 3D screens show a "3D Map Not Available" placeholder on desktop.

## 2. Start it

> **Agent shells don't inherit the interactive environment.** Neither `flutter`
> (`~/flutter/bin`) nor the current `adb` (`~/android-sdk/platform-tools`) is on PATH in
> an agent shell, and the sandbox makes `$HOME` read-only, so flutter tools die with
> `FileSystemException` against **`~/.config/flutter`** (analytics/network config) or
> against **`~/.dart-tool`** (`dart-flutter-telemetry-session.json`). They fail
> separately, and it is the second one that stops `flutter devices` before it lists
> anything.
>
> **The PATH gap is NOT fixed by turning the sandbox off** - it is a shell
> environment issue, not a sandbox issue. Prefix every `bin/dev_*.sh` call
> with the export (verified 2026-09-05: sandbox off but no PATH export still
> fails with `setsid: failed to execute flutter: No such file or directory`):
>
> ```bash
> export PATH="$HOME/flutter/bin:$HOME/android-sdk/platform-tools:$PATH" \
>        ANDROID_HOME="$HOME/android-sdk" ANDROID_SDK_ROOT="$HOME/android-sdk" \
>        XDG_CONFIG_HOME=/tmp/flutter-config XDG_DATA_HOME=/tmp/flutter-data
> bin/dev_run.sh --background
> ```
>
> **Keep `platform-tools` ahead of `/usr/bin`.** The system package at `/usr/bin/adb` is
> Debian's **29.0.6**, `apt` has no newer candidate for it, and it predates the `mdns`
> subcommand — so every wireless-debugging command below dies with
> `adb: unknown command mdns`. `~/.bashrc` already prepends platform-tools, but agent
> shells are non-interactive `bash -c` and never read it, which is why the export is not
> optional here (verified 2026-09-12: `~/android-sdk/platform-tools/adb` is **37.0.0**).
>
> **There are two `adb`s, and the old one is not fixable — don't try.** `/usr/bin/adb` is
> Debian's `android-sdk-platform-tools` (apt-installed 2026-04-08, binary built 2023);
> `~/android-sdk` is Google's SDK, the one Flutter uses, updatable with
> `cmdline-tools/latest/bin/sdkmanager`. All three "obvious" fixes fail or hurt: agent
> shells have no working `sudo` (the sandbox sets `no new privileges`), `/usr/local/bin` is
> a read-only mount owned by `nobody` so the symlink dies with `Permission denied`, and
> removing the Debian package drags `sqlite3`, `graphviz` and the USB udev rules out with
> it (see `docs/setup/WIRELESS_ADB_SETUP.md`). PATH order is the entire fix.
>
> The same export line is all a sandboxed run needs (plain analyze/test only).
>
> **`/tmp` does not persist between agent Bash calls, so never use it as `$HOME`.**
> `XDG_CONFIG_HOME=/tmp/...` is safe because it is re-created inside the one call that
> uses it, but a `/tmp`-based `$HOME` is gone by the next call and adb then fails with
> `Cannot mkdir '/tmp/<name>/.android': No such file or directory` — which reads like a
> broken SDK, not a vanished directory. When `flutter devices` needs a writable `$HOME`,
> point it at a workspace-local one and carry adb's key over:
>
> ```bash
> REAL="$HOME"
> HDIR="$PWD/dev_data/flutter-home"          # inside the gitignored dev_data/
> mkdir -p "$HDIR/.android" && cp -a "$REAL/.android/." "$HDIR/.android/"
> export HOME="$HDIR"
> export PATH="$REAL/flutter/bin:$REAL/android-sdk/platform-tools:$PATH"
> export ANDROID_HOME="$REAL/android-sdk"
> ```
>
> That is what makes `flutter devices` list a paired phone under a `workspace-write`
> sandbox (verified 2026-09-12).

> **Run every `bin/dev_run.sh` with the sandbox disabled** (`dangerouslyDisableSandbox:
> true`). This is not an adb-only rule — it applies to the plain desktop run too. The
> sandbox reaches neither the X11 socket nor the phone's LAN address, and in both cases
> the failure reads as a missing display or a missing phone rather than as a permissions
> problem, so it gets misdiagnosed every time. Same for `bin/dev_reload.sh`,
> `bin/dev_logs.sh`, `bin/dev_screenshot.sh`, and any `adb` command.
>
> **Scope: this section is about Claude Code's bubblewrap sandbox.** It does not describe
> DSH's `workspace-write` policy, which does **not** block the LAN — verified 2026-09-12,
> when `adb mdns services`, `adb pair`, `adb connect`, `adb devices -l` and
> `flutter devices` all succeeded against the Pixel with the sandbox on. Try a sandboxed
> call before escalating for permission; a pre-emptive escalation interrupts the user for
> a grant that is usually unnecessary. `/sandbox` manages the allowlist.
>
> | you see | it is | do |
> |---|---|---|
> | `cannot open display: :0` | the sandbox, hiding X11 | re-run with the sandbox off |
> | `Network is unreachable` | the sandbox, hiding the LAN | re-run with the sandbox off |
> | `flutter pid N is not visible` | the sandbox's own PID namespace | re-run with the sandbox off |
> | `No route to host` | genuinely the network | phone asleep or off Wi-Fi — see below |
>
> The sandbox runs in its own PID namespace, so a healthy app's pid is invisible inside
> it and `kill -0` fails exactly as it would for a dead one. Nothing distinguishes the
> two from in there — which is why `bin/dev_screenshot.sh` names both possibilities
> instead of declaring the app dead.
>
> There **is** a display. Do not conclude the environment is headless and go looking for
> `xvfb` — that has burned a whole verification cycle more than once.

```bash
bin/dev_run.sh --background                 # desktop
bin/dev_run.sh -d "<device>" --background   # Android
```

`--background` detaches the app and returns **only once it is actually up** — or fails
fast with the real error and the tail of the log. Agents should always use it; without it
the command blocks until you quit the app.

**In a fresh worktree, `mkdir -p dev_data` first.** `dev_data/` is gitignored, so a new
worktree has none and `dev_run.sh` dies on its own log redirect with `dev_data/flutter.log:
No such file or directory` — which reads like a build failure. For real data to work with,
copy the main checkout's database in rather than re-seeding from IGC:

```bash
mkdir -p dev_data
cp -r /home/kmcisaac/Projects/the_paragliding_app/dev_data/app_documents dev_data/
```

That database may be an **older schema version**, which is a feature: it exercises the real
upgrade path on launch. Check `[DB:MIGRATE]` and `[CATALOG_RELINK]` in the log afterwards.

Get `<device>` from `flutter devices` (not `adb devices` — Flutter wants its own id). The
wireless Pixel 9 looks like `adb-52110DLAQ001UT-hkZkFs._adb-tls-connect._tcp`. **Always
quote it.**

Other flags: `--profile` (real timings, no hot reload), `--reset` (desktop only, wipes
`dev_data/app_documents` and re-seeds). `-d chrome` runs in a browser.

### Seeding test data (desktop only)

Drop real `.igc` files into `dev_data/igc/`. It is gitignored because those files carry
**real coordinates**. They import on **first launch only** — the seeder runs when the
flights table is empty — so relaunching keeps your data and `--reset` starts over.

Seeding is driven by `--dart-define=SEED_IGC_DIR=...` and handled by
`lib/utils/dev_seed.dart`, which **never runs in a release build**.

```bash
SEED_IGC_LIMIT=20 bin/dev_run.sh --reset   # default is 8; 0 seeds everything
```

Only the **8 most recent** files are imported, ordered by the `YYMMDD` filename prefix. A
full archive is hundreds of files and takes minutes, so drop the whole thing in and raise
the cap only when a task needs more.

## 3. Change code, then reload

```bash
bin/dev_reload.sh      # hot reload  (SIGUSR1 via dev_data/flutter.pid)
bin/dev_reload.sh R    # hot restart (SIGUSR2) - needed after main()/initState changes
```

Works from anywhere, including when the app was started detached — that is what the
script is *for*. If you started it in a terminal yourself, the standard `r` / `R` keys do
the same thing. Confirm it landed —
`Reloaded N libraries in Xms` or `Restarted application in Xms` appears in the log. Do not
assume; a reload that goes nowhere looks exactly like one that worked.

## 4. Look at what happened

```bash
tail -n 50 dev_data/flutter.log                  # recent output
grep -E "\[[IWEDP]\]\[\+" dev_data/flutter.log   # just this app's LoggingService lines
bin/dev_screenshot.sh                            # desktop  -> dev_data/screenshot.png
adb -s "$DEV" exec-out screencap -p > dev_data/screenshot.png   # Android; then Read the PNG
```

For adb use `exec-out`, not `shell` — `shell` mangles the binary. Pass `-s "$DEV"`; there
is usually more than one thing attached.

**On desktop, screenshot with `bin/dev_screenshot.sh` — never a screenshot tool.** No
Wayland capture tool can work in this container, so do not go looking for one: this is
Crostini, `WAYLAND_DISPLAY` is sommelier's socket, and the real compositor is ChromeOS's,
on the host side of the VM. `grim` gets `compositor doesn't support
wlr-screencopy-unstable-v1` and always will — a guest is not allowed to read the host
framebuffer. `scrot` sees only the Xwayland root, which a native-Wayland Flutter window
is not in; that, not multi-monitor, is why it used to return an all-black PNG.

`dev_screenshot.sh` sidesteps the compositor entirely: it asks the Flutter engine for its
last rasterized frame over the VM service `flutter run` already exposes. So it needs no
focus, is unbothered by an obscured or backgrounded window, comes out at full resolution
with no chrome to crop, and **nothing about how the app is launched changes** — desktop
stays native Wayland. It validates the PNG before writing, so a short or non-PNG payload
fails loudly rather than leaving a plausible-looking file. What it returns is the *last
rasterized frame*, so let the UI settle after a hot reload before shooting, or you
capture the frame mid-rebuild and read it as a rendering bug.

It captures the Flutter scene only — no platform views. That costs nothing on Linux (the
3D map is a placeholder there anyway), but on Android prefer `adb exec-out screencap`,
which also gets the Cesium webview and the system UI. The script does work against a
device target, since `flutter run` forwards the VM service to localhost; treat that as
the fallback for when adb is being difficult.

Still worth doing alongside: `dev_data/flutter.log`, and querying
`dev_data/app_documents/FlightLog.db` directly.

### Reading logs from a device

`bin/dev_logs.sh` reads logcat over adb — the only option for a Play Store install, where
there is no `flutter run` at all. There is no logcat on Linux desktop, so `flutter.log`
remains the only log there, and it is also the only place build and compile errors appear.

```bash
bin/dev_logs.sh --keys       # just the [API_KEYS_STATUS] line
bin/dev_logs.sh -g cesium    # search the whole buffer
bin/dev_logs.sh -f           # follow live
bin/dev_logs.sh --tee        # follow live, appending to dev_data/logcat.log
```

**The logcat ring buffer is too small to read after the fact, and it is not `adbd`'s
fault.** The project blamed `adbd` retrying a USB bind for years; measuring it on
2026-08-11 found the real source is `android.hardware.thermal-service.pixel`, which logs
one `I pixel-thermal:` line per sensor per poll — 84.5 lines/s, 79% of the buffer, leaving
**~30 seconds** of retention in the 256 KiB default. The wrong attribution sent a
debugging session looking at USB and adb, so prefer the numbers over the story:

```bash
adb shell setprop persist.log.tag.pixel-thermal S        # survives reboot, needs no root
adb shell setprop persist.log.tag.libPixelUsbOverheat S  # the second-largest source
adb shell logcat -G 4M     # re-apply each boot - persist.logd.size is refused without root
```

Measured after: **9.5 lines/s and ~65 min** of retention. `trusty` looks like the biggest
flooder in a plain `logcat -d` histogram and is a red herring — it is in the **kernel**
buffer, a separate 256 KiB ring that costs the app's log nothing.

Even 65 minutes is still a ring, so for anything you intend to read later use
`bin/dev_logs.sh --tee`: it copies the filtered stream to a host file where nothing ages
out. It appends and brackets each run with a marker, for the same reason `flutter.log` has
an exit marker — a capture that died with the adb connection must not read as an app with
nothing to say. The phone also dozes when idle, which kills `flutter run` (and with it
`dev_input.sh`, though not the app); Developer options → **"Stay awake"** avoids it.

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

## Driving the UI

Allowed as of 2026-08-08 — it used to say "ask the user to navigate". Navigate to the
screen under test and look at it yourself; a UI fix nobody has looked at is unverified.

Works on both targets now, by completely different routes. Desktop was Android-only until
2026-08-10.

### Desktop: `bin/dev_input.sh`

```bash
bin/dev_input.sh tap 598 1004              # tap the Log Book nav item
bin/dev_input.sh scroll 478 500 900        # wheel down 900px at that point
bin/dev_input.sh scroll 478 500 -900       # ... and back up
bin/dev_input.sh drag 478 800 478 300 400  # drag up over 400ms
```

**Coordinates are screenshot pixels**, straight off `bin/dev_screenshot.sh` — the script
divides by `devicePixelRatio` itself. That ratio is 1.0 on this desktop, so a missing
conversion would look correct here and break on any HiDPI box; it is done in one place
rather than left to the caller.

Nothing was added to the app to make this work, and nothing needs to be. It evaluates Dart
in the running isolate over the VM service — `GestureBinding.handlePointerEvent`, the same
entry point the widget-test framework drives, which does its own hit test. No compositor
involved, which is the whole point: `xdotool` cannot reach native-Wayland windows, and
sommelier exposes neither the virtual-keyboard nor the virtual-pointer protocol, so
`wtype` and `ydotool` are out. Same reasoning as `dev_screenshot.sh` going to the engine
rather than to `grim`.

Four things about it are worth knowing before you debug it:

- **It dies with `flutter run`, not with the app.** Expression evaluation needs the
  `compileExpression` service that `flutter run` registers, so it goes away the moment
  flutter detaches even if the app is still on screen. `dev_run.sh` removes the pid file
  then, and the script refuses on that — same readiness check as `dev_screenshot.sh`.
- **No text entry.** Tapping a field moves the caret, but the engine owns the keyboard
  channel and there is nothing to type on. Use the phone for anything involving typing.
- **Platform views are not driven** (and not captured) — free on Linux, where the 3D map
  is a placeholder anyway.
- **A throw lands in `flutter.log`, not in the exit code**, because events are queued onto
  the app's event loop instead of run inline. The script greps its own slice of the log for
  `[DEV_INPUT] ERROR` and exits 1, so a failed injection cannot look like a success. That
  check was verified by making it fail on purpose.

The queueing is load-bearing, not incidental. The VM runs an evaluation at the next
safepoint, which can be *inside* `drawFrame`; dispatching a pointer event from there
reenters the framework mid-build and the scroll handler throws `setState() called during
build`. It only bites once something is animating — a tap on an idle app looks perfect and
a drag fails on its second move. Related trap: an evaluated closure shows up in a stack
trace as a bare `Eval ()` frame with no file or line, which fails an assertion inside
`StackFrame.fromStackTraceLine`, so a real exception surfaces as a confusing regex-match
assertion. If you see one of those, look for the underlying error, not for a Flutter bug.

### Android: `adb shell input`

```bash
DEV=adb-52110DLAQ001UT-hkZkFs._adb-tls-connect._tcp
adb -s "$DEV" shell input tap <x> <y>              # coordinates are DEVICE px, not dp
adb -s "$DEV" shell input swipe <x1> <y1> <x2> <y2> <ms>   # drag a sheet; ms>300 or it flings
adb -s "$DEV" shell input text "Bakewell"          # %s for spaces
adb -s "$DEV" shell input keyevent KEYCODE_BACK    # 4=back, 3=home, 111=escape
adb -s "$DEV" exec-out screencap -p > dev_data/screenshot.png
```

Under Claude Code this needs the sandbox off, like everything else that reaches the phone;
under DSH it works as-is — see the scoping note at the end of the wireless section.

- **Coordinates are device pixels, and adb will not convert them for you** — unlike
  `dev_input.sh`. The Pixel 9 is 1080x2424 px at dpr 2.625, so a widget at 200dp from the
  left is at x=525. Read a screenshot to find a target — never guess from Flutter layout
  numbers.

### Both targets

- **Screenshot after every step, before the next.** Taps land on whatever is there now, and
  a tap that misses looks identical to one that worked until you look.
- **Let the frame settle** — `sleep 1` between a tap and its screenshot, or the capture
  catches a half-built route mid-animation and reads as a rendering bug.
- **Read `dev_data/flutter.log` alongside.** An overflow or exception caused by your own
  navigation is a real finding; one caused by a mistap is noise. The log tells them apart.
- Still true on Android: **never `pm clear`/`pm uninstall`** anything, suffixed or not, and
  unlock the phone first — a screenshot of a locked phone is a valid PNG of the lock screen.

## Wireless debugging (physical device)

```bash
# On the phone: Settings > System > Developer options > Wireless debugging
ADB="$HOME/android-sdk/platform-tools/adb"       # bare `adb` may be the 29.0.6 system one
"$ADB" pair <ip>:<pairing-port> <6-digit-code>   # "Pair device with pairing code" dialog
"$ADB" connect <ip>:<connect-port>               # DIFFERENT port, on the main screen
flutter devices                                  # confirm, then use the id with -d
```

The pairing port and the connect port are different — mixing them up is the usual failure.
Pairing is permanent; re-run only `adb connect` in later sessions. A stale pairing dialog
leaves its port listening but dead, which surfaces as `error: protocol fault (couldn't read
status message)` — reopen the dialog for a fresh port and code.

**A third case looks like the second and is not: `failed to connect` while mdns lists the
phone and its port is open means the phone is not paired with *this host's* key.** Re-pair,
taking both addresses from mdns in the same shell:

```bash
ADB="$HOME/android-sdk/platform-tools/adb"       # NOT bare adb — see the export note in §2
PAIR=$("$ADB" mdns services | awk '/_adb-tls-pairing/{print $NF}')
CONN=$("$ADB" mdns services | awk '/_adb-tls-connect/{print $NF}')
"$ADB" pair "$PAIR" <6-digit-code>   # code from the "Pair device with pairing code" dialog
"$ADB" connect "$CONN"
```

Observed exactly this on 2026-09-12: `adb connect 192.168.86.144:44457` failed repeatedly
with a *correct* address while the port accepted TCP and mdns advertised it; `adb pair`
succeeded and the very next `connect` worked. Check pairing before hunting for a port typo.
The pairing port and code both change whenever the dialog is reopened and the code expires
in ~1-2 minutes, so discover the port immediately before pairing.

**`adb mdns services` works from a Crostini container** and is the fastest way to find the
phone after DHCP moves it — it reports the live `IP:port` for both services directly,
rather than reading a possibly-stale IP off the phone's dialog:

```bash
ADB="$HOME/android-sdk/platform-tools/adb"   # bare `adb` is Debian's 29.0.6: "unknown command mdns"
"$ADB" mdns services | awk '/_adb-tls-connect/{print $NF}'   # connect port
"$ADB" mdns services | awk '/_adb-tls-pairing/{print $NF}'   # pairing port - only while the dialog is open
```

An earlier version of this note claimed it "always returns empty" on the theory that
multicast doesn't cross the Crostini NAT — that was wrong, verified 2026-08-11, and cost
real debugging time before someone just tried it.

**It is also flaky, which is a different thing from absent.** On 2026-09-12 it returned an
empty list on 4 of 6 calls, twice consecutively, and found the phone on the next attempt.
Retry two or three times before concluding anything — one empty result proves nothing, and
neither does a `connect` failure that follows it.

### Run `adb devices -l` before connecting anything

The paired TLS transport reconnects by itself, so the phone is usually already there:

```
192.168.86.144:44457   device product:tokay model:Pixel_9 device:tokay transport_id:1
```

No `adb connect` needed. **Trust no address recorded in this file or in the setup doc** — the
phone is on DHCP and moves (it was `192.168.86.99` on 2026-08-08 and `192.168.86.144` on
2026-09-12); get the live one from `adb mdns services`. Three things that look like an
absent phone and are not:

- **`flutter devices` listing only Linux and Chrome.** It can miss a transport `adb` sees.
  Check both before concluding the phone is unplugged.
- **A failing `adb connect`.** On 2026-08-08 `adb connect 192.168.86.99:5555` returned
  `No route to host` while `adb devices -l` showed the phone online on the next line, and
  the app deployed to it fine.
- **`failed to connect` while mdns advertises it, on an open port.** The host is not paired;
  run `adb pair` — see "A third case looks like the second" above.

### adb over the LAN needs the sandbox off — under Claude Code only

Under Claude Code, agent Bash commands run inside a **bubblewrap sandbox** whose network
allowlist covers pub.dev, GitHub and the app's APIs — **not the phone's LAN address**.
Anything that has to reach the phone over Wi-Fi fails there with:

```
failed to connect to '192.168.86.99:5555': Network is unreachable
```

`Network is unreachable` is that sandbox. `No route to host` is the network. Re-run with the
sandbox disabled — that includes `bin/dev_run.sh -d "<device>"`, which talks to the phone
right through the build-install-attach cycle, not only at connect time. `/sandbox` manages
the allowlist if this becomes routine.

**Under DSH this section does not apply** (verified 2026-09-12): with the `workspace-write`
sandbox on, `adb mdns services`, `adb pair 192.168.86.144:39267 <code>`,
`adb connect 192.168.86.144:44457`, `adb devices -l` and `flutter devices` all worked. The
commands to disable the sandbox are in §2 with the same scoping note — read it before
escalating, and prefer one sandboxed attempt over an approval prompt.
