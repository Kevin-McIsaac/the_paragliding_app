#!/usr/bin/env bash
#
# Pull logs off an Android device - including a Play Store install, where there is
# no `flutter run` and so no dev_data/flutter.log to read.
#
#   bin/dev_logs.sh                  # last 300 lines of app-relevant logcat
#   bin/dev_logs.sh -n 1000          # more scrollback
#   bin/dev_logs.sh -f               # follow live
#   bin/dev_logs.sh --keys           # just the [API_KEYS_STATUS] line
#   bin/dev_logs.sh -g cesium        # search the whole buffer, any tag (case-sensitive)
#   bin/dev_logs.sh --raw            # unfiltered logcat (all tags)
#   bin/dev_logs.sh -c               # clear the buffer, then exit
#
# Connection is handled here: an already-online device is used as-is, otherwise the
# known phone IPs are tried on the fixed tcpip port. `adb tcpip 5555` resets on phone
# reboot - if every candidate fails, re-run it over USB (see the run-app skill).
#
# What a release install actually logs: LoggingService gates release builds at
# Level.warning, so info/debug from our own code is absent by design. What survives is
# warnings, errors, and the [API_KEYS_STATUS] structured line - which exists precisely
# to answer "did this Play-delivered build get its --dart-define secrets?". Empty
# airspace overlays and a blank 3D map are what a keyless build looks like.
#
# WebView console output (Cesium JS errors) arrives under the chromium tag, not
# flutter - which is why the default filter includes both.

set -euo pipefail

# Pixel 9 (tokay). .99 is the current lease, .135 was an earlier one.
CANDIDATE_IPS=("192.168.86.99" "192.168.86.135")
ADB_PORT=5555

lines=300
follow=false
raw=false
clear_first=false
pattern=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--lines)
      # ${2-} not $2: under `set -u` a bare `-n` would otherwise die with an
      # unbound-variable trace instead of saying what was wrong.
      lines="${2-}"
      [[ -n "$lines" ]] || { echo "$1 needs a line count (try --help)" >&2; exit 1; }
      shift 2
      ;;
    -f|--follow)
      follow=true
      shift
      ;;
    --raw)
      raw=true
      shift
      ;;
    --keys)
      # The one line that is meaningful in a release install (see the note above).
      pattern="API_KEYS_STATUS"
      raw=true
      shift
      ;;
    -g|--grep)
      pattern="${2-}"
      [[ -n "$pattern" ]] || { echo "$1 needs a pattern (try --help)" >&2; exit 1; }
      raw=true
      shift 2
      ;;
    -c|--clear)
      clear_first=true
      shift
      ;;
    -h|--help)
      sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown option: $1 (try --help)" >&2
      exit 1
      ;;
  esac
done

# An online device is good enough however it got connected - the guid-based TLS
# transport from `adb pair` reconnects by itself and needs no `adb connect`.
online_device() {
  adb devices | awk '$2 == "device" { print $1; exit }'
}

device="$(online_device || true)"
if [[ -z "$device" ]]; then
  for ip in "${CANDIDATE_IPS[@]}"; do
    echo "connecting to $ip:$ADB_PORT ..." >&2
    timeout 10 adb connect "$ip:$ADB_PORT" >/dev/null 2>&1 || true
    device="$(online_device || true)"
    [[ -n "$device" ]] && break
  done
fi

if [[ -z "$device" ]]; then
  cat >&2 <<'EOF'
No device. Either the phone is off the network, or `adb tcpip 5555` has not been run
since its last reboot. Plug in over USB and:

    adb tcpip 5555

then unplug and re-run this script. Wireless Debugging pairing (a random port, needs
re-pairing) is the fallback - see the run-app skill.
EOF
  exit 1
fi

echo "device: $device" >&2

if $clear_first; then
  adb -s "$device" logcat -c
  echo "logcat buffer cleared" >&2
  exit 0
fi

# flutter carries our own LoggingService output; chromium carries WebView console
# messages, which is where Cesium reports its own failures. The rest are the tags
# that speak up when a WebView or a native plugin goes wrong.
TAGS=(flutter:V chromium:V InAppWebView:V AndroidRuntime:E System.err:W "*:S")
$raw && TAGS=()

# `-t N` is deliberately not used: logcat applies it to the raw buffer *before* the
# tag filterspec, so `-t 400 flutter:V *:S` silently prints nothing whenever the last
# 400 raw lines happen to hold no flutter line. Dump the filtered stream and tail it.
if $follow; then
  if [[ -n "$pattern" ]]; then
    # --line-buffered matters: without it grep emits in 4KB blocks, so a live follow
    # looks frozen between bursts. Piping rather than exec'ing keeps the pattern
    # applied - an earlier version exec'd straight into logcat here, silently
    # dropping -g/--keys and handing back an unfiltered firehose that looked filtered.
    adb -s "$device" logcat "${TAGS[@]}" | grep --line-buffered -a -E "$pattern"
  else
    adb -s "$device" logcat "${TAGS[@]}"
  fi
  exit
fi

out="$(adb -s "$device" logcat -d "${TAGS[@]}")"

if [[ -n "$pattern" ]]; then
  # grep finding nothing is an ordinary result here, not a failure worth set -e
  out="$(grep -a -E "$pattern" <<<"$out" || true)"
  if [[ -z "$out" ]]; then
    echo "no match for /$pattern/ in the buffer" >&2
    exit 1
  fi
fi

tail -n "$lines" <<<"$out"
