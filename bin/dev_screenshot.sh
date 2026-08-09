#!/usr/bin/env bash
#
# Screenshot the app running on Linux desktop, without touching the compositor.
#
#   bin/dev_screenshot.sh                # -> dev_data/screenshot.png
#   bin/dev_screenshot.sh -o shot.png    # write somewhere else
#
# Needs an app started by bin/dev_run.sh (debug or profile - a release build has no
# VM service). Run it with the sandbox disabled, like the rest of bin/.
#
# Why not a screenshot tool: this box is Crostini, so WAYLAND_DISPLAY is sommelier's
# socket and the real compositor is ChromeOS's, on the host side of the VM. grim gets
# "compositor doesn't support wlr-screencopy-unstable-v1" - a guest container is not
# allowed to read the host framebuffer, and no Wayland capture tool will change that.
# scrot only sees the Xwayland root, which a native-Wayland Flutter window is not in;
# that is the all-black PNG this project used to blame on multi-monitor. So capture
# from the engine instead: the Flutter engine registers a _flutter.screenshot service
# extension returning the last rasterized frame as a base64 PNG, and the VM service
# answers plain HTTP GET. Nothing about how the app runs has to change.
#
# It captures the Flutter scene only - no window decorations, and no platform views.
# That costs nothing on Linux (flutter_inappwebview has no Linux implementation, so
# the 3D map is a placeholder there anyway). On Android prefer
# `adb exec-out screencap`, which also gets the Cesium webview and the system UI; this
# script does work against a device target, since flutter run forwards the VM service
# to localhost, but it is the fallback there rather than the default.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$REPO_ROOT/dev_data/flutter.pid"
LOG_FILE="$REPO_ROOT/dev_data/flutter.log"
out="$REPO_ROOT/dev_data/screenshot.png"
timeout_s="${DEV_SCREENSHOT_TIMEOUT:-30}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out)
      # ${2-} not $2: under `set -u` a bare -o would die with an unbound-variable
      # trace instead of saying what was wrong.
      out="${2-}"
      [[ -n "$out" ]] || { echo "ERROR: $1 requires a path" >&2; exit 1; }
      shift 2
      ;;
    -h|--help)
      # Print the header comment block, as bin/dev_run.sh does.
      awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument '$1' (try --help)" >&2
      exit 1
      ;;
  esac
done

for cmd in curl jq base64; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd is required but not installed" >&2; exit 1; }
done

# Liveness first, same check as bin/dev_reload.sh: flutter writes the pid file only
# once the app is up and removes it on exit, so it *is* the readiness check.
if [[ ! -f "$PID_FILE" ]]; then
  echo "ERROR: $PID_FILE not found - is the app running via bin/dev_run.sh?" >&2
  exit 1
fi
pid="$(cat "$PID_FILE")"
if ! kill -0 "$pid" 2>/dev/null; then
  # Do not call this a stale pid file, the way dev_reload.sh can afford to. The agent
  # sandbox runs in its own PID namespace, so a perfectly healthy app is invisible
  # here and a confident "not running" would be a lie. Nothing distinguishes the two
  # cases from inside, so say both.
  echo "ERROR: flutter pid $pid is not visible from here. Either:" >&2
  echo "       - the app has stopped, and $PID_FILE is stale; or" >&2
  echo "       - you are in the agent sandbox, which hides host processes and blocks" >&2
  echo "         localhost, so a running app looks exactly like a dead one." >&2
  echo "       If the app is running, re-run with the sandbox disabled." >&2
  exit 1
fi

# Anchor on the "Dart VM Service" line. A looser match for an http://127.0.0.1 URL
# also hits the DevTools line printed right after it, and picking that one yields an
# HTML page and a 0-byte screenshot with no error anywhere.
uri="$(sed -n 's#.*Dart VM Service.*available at: \(http://[^ ]*\)#\1#p' "$LOG_FILE" 2>/dev/null | tail -1)"
if [[ -z "$uri" ]]; then
  echo "ERROR: no VM service URL in $LOG_FILE." >&2
  echo "       A release build has none; otherwise restart with bin/dev_run.sh --background." >&2
  exit 1
fi

response="$(mktemp "${TMPDIR:-/tmp}/dev_screenshot.XXXXXX")"
trap 'rm -f "$response"' EXIT

rc=0
curl_err="$(curl -sS --max-time "$timeout_s" "${uri}_flutter.screenshot" -o "$response" 2>&1)" || rc=$?
if (( rc != 0 )); then
  # We only get here with a live pid, so a refused connection is not a dead app -
  # it is the agent sandbox, which blocks localhost. Same misdiagnosis as
  # "cannot open display: :0" for X11 and "Network is unreachable" for the phone.
  if (( rc == 7 )); then
    hostport="${uri#*//}"
    hostport="${hostport%%/*}"
    echo "ERROR: cannot reach the VM service at $hostport while flutter pid $pid is alive." >&2
    echo "       That is the agent sandbox blocking localhost, not a stopped app." >&2
    echo "       Re-run with the sandbox disabled (dangerouslyDisableSandbox: true)." >&2
  else
    echo "ERROR: curl failed (exit $rc): $curl_err" >&2
  fi
  exit 1
fi

# JSON-RPC over GET answers either {"result":{...}} or {"error":{"message":...}}.
if ! jq -e 'has("result") and (.result.screenshot | type == "string")' "$response" >/dev/null 2>&1; then
  err_msg="$(jq -r '.error.message // empty' "$response" 2>/dev/null || true)"
  if [[ -n "$err_msg" ]]; then
    echo "ERROR: the VM service rejected _flutter.screenshot: $err_msg" >&2
  else
    echo "ERROR: unexpected response from the VM service (first 200 bytes):" >&2
    head -c 200 "$response" >&2
    echo >&2
  fi
  exit 1
fi

mkdir -p "$(dirname "$out")"
# Decode beside the destination and move into place, so a failed or truncated decode
# never leaves a plausible-looking file where the caller will read it as current.
tmp_png="$(mktemp "${out}.XXXXXX")"
trap 'rm -f "$response" "$tmp_png"' EXIT
jq -r '.result.screenshot' "$response" | base64 -d >"$tmp_png" ||
  { echo "ERROR: could not decode the screenshot payload" >&2; exit 1; }

# Check the artifact, not the exit code. An empty or truncated capture is a valid-
# looking PNG path with nothing in it, and that reads as "the app rendered nothing".
magic="$(head -c 8 "$tmp_png" | od -An -tx1 | tr -d ' \n')"
if [[ "$magic" != "89504e470d0a1a0a" ]]; then
  echo "ERROR: decoded payload is not a PNG (magic: ${magic:-empty})" >&2
  exit 1
fi
bytes="$(stat -c %s "$tmp_png")"
if (( bytes < 1000 )); then
  echo "ERROR: screenshot is only $bytes bytes - truncated, not a real frame" >&2
  exit 1
fi

mv "$tmp_png" "$out"
trap 'rm -f "$response"' EXIT
echo "Wrote $out ($bytes bytes, $(file -b "$out" 2>/dev/null | cut -d, -f2- | sed 's/^ //'))"
