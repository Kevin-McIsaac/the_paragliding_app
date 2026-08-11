#!/usr/bin/env bash
#
# Pull logs off an Android device - including a Play Store install, where there is
# no `flutter run` and so no dev_data/flutter.log to read.
#
#   bin/dev_logs.sh                  # last 300 lines of app-relevant logcat
#   bin/dev_logs.sh -n 1000          # more scrollback
#   bin/dev_logs.sh -f               # follow live
#   bin/dev_logs.sh --tee            # follow live, appending to dev_data/logcat.log
#   bin/dev_logs.sh --tee out.log    # ... to a path of your choosing
#   bin/dev_logs.sh --keys           # just the [API_KEYS_STATUS] line
#   bin/dev_logs.sh -g cesium        # search the whole buffer, any tag (case-sensitive)
#   bin/dev_logs.sh --raw            # unfiltered logcat (all tags)
#   bin/dev_logs.sh -c               # clear the buffer, then exit
#   bin/dev_logs.sh -s <id>          # pick a device when more than one is online
#
# --tee exists because the ring buffer is too small to be read after the fact. On the
# Pixel 9 the `main` buffer is the 256 KiB default and `android.hardware.thermal-service.pixel`
# writes one `I pixel-thermal:` line per sensor per poll - measured at 84.5 lines/s, which
# is 79% of the buffer and leaves about 30 seconds of retention. Two unprivileged setprops
# fix the source (they need no root, and the persist ones survive reboot):
#
#     adb shell setprop persist.log.tag.pixel-thermal S
#     adb shell setprop persist.log.tag.libPixelUsbOverheat S
#     adb shell logcat -G 4M        # re-apply each boot; persist.logd.size needs root
#
# That measured 84.5 -> 9.5 lines/s and ~30 s -> ~65 min of retention. Even so, 65 minutes
# is still a ring: `--tee` copies the filtered stream to a file on the host, where nothing
# ages out and the buffer size stops mattering at all. It appends rather than truncating,
# and brackets each run with a marker, so a stream that died with the adb connection cannot
# be mistaken for one that had nothing to report - the same reasoning as flutter.log's
# exit marker.
#
# Connection is handled here: a single online device is used as-is, otherwise the
# known phone IPs are tried on the fixed tcpip port. `adb tcpip 5555` resets on phone
# reboot - if every candidate fails, re-run it over USB (see the run-app skill).
#
# With more than one device online the script refuses to guess and asks for -s (or
# ANDROID_SERIAL). Reading the wrong phone's logs is the exact failure this script
# exists to prevent - it would answer confidently about the install you did not mean.
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

# Fallback IPs, tried only when no device is already online. Pixel 9 (tokay); .99 is
# the current lease, .135 an earlier one. Not portable between developers - override
# with DEV_LOGS_IPS="192.168.1.20 192.168.1.21", or just edit this line.
read -r -a CANDIDATE_IPS <<<"${DEV_LOGS_IPS:-192.168.86.99 192.168.86.135}"
ADB_PORT=5555

lines=300
follow=false
raw=false
clear_first=false
pattern=""
requested=""
tee_file=""
TEE_DEFAULT="dev_data/logcat.log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--lines)
      # ${2-} not $2: under `set -u` a bare `-n` would otherwise die with an
      # unbound-variable trace instead of saying what was wrong. Reject 0 along with
      # non-numerics: `tail -n 0` prints nothing, which reads as an empty buffer.
      lines="${2-}"
      [[ "$lines" =~ ^[1-9][0-9]*$ ]] ||
        { echo "$1 needs a positive line count, got '$lines' (try --help)" >&2; exit 1; }
      shift 2
      ;;
    -f|--follow)
      follow=true
      shift
      ;;
    --tee)
      # The path is optional. Consume the next argument only when it is not itself a
      # flag, so `--tee -g cesium` keeps the default file instead of swallowing the -g
      # and then failing on a stray pattern.
      tee_file="$TEE_DEFAULT"
      if [[ -n "${2-}" && "${2-}" != -* ]]; then
        tee_file="$2"
        shift
      fi
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
    -s|--serial)
      requested="${2-}"
      [[ -n "$requested" ]] || { echo "$1 needs a device id (try --help)" >&2; exit 1; }
      shift 2
      ;;
    -h|--help)
      # Print the header comment block - from after the shebang to the first
      # non-comment line - rather than a fixed line range, which silently truncated
      # or picked up code whenever a header line was added.
      awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "unknown option: $1 (try --help)" >&2
      exit 1
      ;;
  esac
done

# An online device is good enough however it got connected - the guid-based TLS
# transport from `adb pair` reconnects by itself and needs no `adb connect`. Every
# online id is listed, not just the first: picking the first silently read whichever
# device adb happened to list first whenever a second phone or an emulator was up.
online_devices() {
  adb devices | awk '$2 == "device" { print $1 }'
}

# -s wins over ANDROID_SERIAL; adb's own env var is honoured so this behaves like adb.
requested="${requested:-${ANDROID_SERIAL-}}"

mapfile -t devices < <(online_devices || true)

# Only reconnect when nothing at all is online - an explicit -s for a device that is
# already up must not drag the candidate IPs in.
if [[ ${#devices[@]} -eq 0 ]]; then
  for ip in "${CANDIDATE_IPS[@]}"; do
    echo "connecting to $ip:$ADB_PORT ..." >&2
    timeout 10 adb connect "$ip:$ADB_PORT" >/dev/null 2>&1 || true
    mapfile -t devices < <(online_devices || true)
    [[ ${#devices[@]} -gt 0 ]] && break
  done
fi

if [[ ${#devices[@]} -eq 0 ]]; then
  cat >&2 <<'EOF'
No device. Either the phone is off the network, or `adb tcpip 5555` has not been run
since its last reboot. Plug in over USB and:

    adb tcpip 5555

then unplug and re-run this script. Wireless Debugging pairing (a random port, needs
re-pairing) is the fallback - see the run-app skill.
EOF
  exit 1
fi

if [[ -n "$requested" ]]; then
  device=""
  for d in "${devices[@]}"; do
    [[ "$d" == "$requested" ]] && device="$d" && break
  done
  if [[ -z "$device" ]]; then
    echo "device '$requested' is not online. Online now:" >&2
    printf '  %s\n' "${devices[@]}" >&2
    exit 1
  fi
elif [[ ${#devices[@]} -gt 1 ]]; then
  # Refusing beats guessing: these logs get read as evidence about one specific
  # install, so the wrong device is worse than no output at all.
  echo "more than one device online - pick one with -s <id> (or ANDROID_SERIAL):" >&2
  printf '  %s\n' "${devices[@]}" >&2
  exit 1
else
  device="${devices[0]}"
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
# Copy the stream to the tee file as well as stdout, so a --tee run stays readable live
# (and greppable by the Monitor tool) instead of going silently into a file.
sink() {
  if [[ -n "$tee_file" ]]; then
    tee -a "$tee_file"
  else
    cat
  fi
}

if [[ -n "$tee_file" ]]; then
  mkdir -p "$(dirname "$tee_file")"
  printf -- '--- tee started %s - device %s ---\n' "$(date '+%F %T')" "$device" >>"$tee_file"
  # Without an end marker a file that stopped because adb dropped the connection is
  # indistinguishable from one where the app simply went quiet - the mistake flutter.log
  # already learned to prevent.
  trap 'printf -- "--- tee ended %s - stream stopped; the app may still be running ---\n" \
    "$(date "+%F %T")" >>"$tee_file"' EXIT
  echo "teeing to $tee_file" >&2
fi

if $follow; then
  # -T 1 starts at the end of the buffer, and only in --tee mode: a tee restarted after
  # a dropped connection must not re-append the whole ring it already captured. A plain
  # -f still dumps history first, which is what you want reading interactively.
  #
  # Note this is not the `-t N` trap described above: -t caps the output at N raw lines,
  # so the tag filterspec can leave nothing at all, whereas -T 1 only sets the start
  # point and then follows forever.
  start=()
  [[ -n "$tee_file" ]] && start=(-T 1)
  if [[ -n "$pattern" ]]; then
    # --line-buffered matters: without it grep emits in 4KB blocks, so a live follow
    # looks frozen between bursts. Piping rather than exec'ing keeps the pattern
    # applied - an earlier version exec'd straight into logcat here, silently
    # dropping -g/--keys and handing back an unfiltered firehose that looked filtered.
    adb -s "$device" logcat "${start[@]}" "${TAGS[@]}" \
      | grep --line-buffered -a -E "$pattern" | sink
  else
    adb -s "$device" logcat "${start[@]}" "${TAGS[@]}" | sink
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
