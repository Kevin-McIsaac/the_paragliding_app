#!/usr/bin/env bash
#
# Tap, scroll and drag the app running on Linux desktop, without touching the
# compositor.
#
#   bin/dev_input.sh tap 598 1004              # tap the Log Book nav item
#   bin/dev_input.sh scroll 478 500 900        # wheel down 900px at that point
#   bin/dev_input.sh scroll 478 500 -900       # ... and back up
#   bin/dev_input.sh drag 478 800 478 300 400  # drag up over 400ms
#
# Coordinates are SCREENSHOT pixels, straight off bin/dev_screenshot.sh - the
# script divides by devicePixelRatio itself, so there is no conversion to get
# wrong. Origin is top-left. Positive scroll dy moves content up (scrolls down).
#
# Needs an app started by bin/dev_run.sh (debug, and still attached to
# `flutter run`). Run it with the sandbox disabled, like the rest of bin/.
#
# Why this is not just a curl, like bin/dev_screenshot.sh: there is no engine
# service extension for pointer input - the engine registers _flutter.screenshot
# and friends and nothing for events. So this evaluates Dart in the running
# isolate instead, calling GestureBinding.handlePointerEvent, which is the same
# entry point the widget-test framework drives and which does its own hit test.
#
# That needs the VM service's `evaluate`, and evaluate needs an expression
# compiler, which `flutter run` registers as a compileExpression service. That
# service is only reachable over the *websocket*: the same request over the HTTP
# GET endpoint fails with "No compilation service available". Hence a websocket
# client, hence dev_input.dart - dart:io has one built in, so it needs no
# packages and no pubspec.
#
# Consequences worth knowing:
#   - It dies with `flutter run`. Once dev_data/flutter.log shows the
#     "--- flutter exited ---" marker there is no expression compiler any more,
#     even if the app is still on screen.
#   - It injects below the platform, so it drives Flutter's gesture path and not
#     the window's: no IME text entry, no native menus, no platform views. Same
#     trade bin/dev_screenshot.sh already makes, and free on Linux where the 3D
#     map is a placeholder anyway.
#   - Text entry is NOT supported. Tap a field and the caret moves, but there is
#     no keyboard to type on - the engine owns that channel. Use the phone.
#
# On Android prefer `adb shell input tap/swipe`, which goes through the real
# input stack. This is the desktop equivalent, not a replacement for it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$REPO_ROOT/dev_data/flutter.pid"
LOG_FILE="$REPO_ROOT/dev_data/flutter.log"

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  # Print the header comment block, as bin/dev_screenshot.sh does.
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
  # No arguments at all is a usage error, not a request for help.
  if [[ $# -eq 0 ]]; then exit 1; fi
  exit 0
fi

# Liveness first, same check as bin/dev_screenshot.sh: flutter writes the pid
# file only once the app is up and removes it on exit, so it *is* the readiness
# check.
if [[ ! -f "$PID_FILE" ]]; then
  echo "ERROR: $PID_FILE not found - is the app running via bin/dev_run.sh?" >&2
  exit 1
fi
pid="$(cat "$PID_FILE")"
if ! kill -0 "$pid" 2>/dev/null; then
  # Not necessarily a stale pid file: the agent sandbox runs in its own PID
  # namespace, so a healthy app is invisible from in there and looks exactly
  # like a dead one. Say both rather than guess.
  echo "ERROR: flutter pid $pid is not visible from here. Either:" >&2
  echo "       - the app has stopped, and $PID_FILE is stale; or" >&2
  echo "       - you are in the agent sandbox, which hides host processes and blocks" >&2
  echo "         localhost, so a running app looks exactly like a dead one." >&2
  echo "       If the app is running, re-run with the sandbox disabled." >&2
  exit 1
fi

# Anchor on the "Dart VM Service" line. A looser match for an http://127.0.0.1
# URL also hits the DevTools line printed right after it.
uri="$(sed -n 's#.*Dart VM Service.*available at: \(http://[^ ]*\)#\1#p' "$LOG_FILE" 2>/dev/null | tail -1)"
if [[ -z "$uri" ]]; then
  echo "ERROR: no VM service URL in $LOG_FILE." >&2
  echo "       A release build has none; otherwise restart with bin/dev_run.sh --background." >&2
  exit 1
fi

# No separate check that flutter is still attached: the pid file above is that
# check. dev_run.sh removes it when flutter exits, which is exactly when the
# expression compiler goes away, so a missing pid file already means "no input".
ws="ws://${uri#http://}ws"

# Prefer the dart beside the flutter that built the app, so this cannot pick up
# a different SDK from PATH.
if command -v flutter >/dev/null; then
  DART="$(dirname "$(readlink -f "$(command -v flutter)")")/dart"
fi
if [[ ! -x "${DART:-}" ]]; then
  DART="$(command -v dart || true)"
fi
if [[ -z "$DART" ]]; then
  echo "ERROR: no dart executable found (looked beside flutter, then on PATH)" >&2
  exit 1
fi

# Events are queued onto the app's event loop rather than run inline (see
# dev_input.dart), so the dart process exits before they are handled and a throw
# lands in the app's log instead of in our exit code. Watch the slice of log
# this invocation produced, or a tap that asserted exits 0 and reads as working.
log_before="$(wc -c <"$LOG_FILE")"

# Capturing rc must not go through set -e, or a dart failure would skip the
# log check below and lose the more useful error.
rc=0
"$DART" "$REPO_ROOT/bin/dev_input.dart" "$ws" "$@" || rc=$?

# Let the queued events run and their output reach the log before judging.
sleep 0.5
if tail -c "+$((log_before + 1))" "$LOG_FILE" | grep -q '\[DEV_INPUT\] ERROR'; then
  echo "ERROR: the injected event threw inside the app:" >&2
  tail -c "+$((log_before + 1))" "$LOG_FILE" | grep '\[DEV_INPUT\] ERROR' >&2
  exit 1
fi
exit "$rc"
