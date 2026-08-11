#!/usr/bin/env bash
#
# Run the app on Linux desktop, or on any flutter device with -d.
#
#   bin/dev_run.sh                   # desktop, seeding on first launch (empty database)
#   bin/dev_run.sh --reset           # wipe dev database + app documents, then run
#   bin/dev_run.sh --profile         # profile build, for timing without debug overhead
#   bin/dev_run.sh -d "<device>"     # another device - get ids from: flutter devices
#   bin/dev_run.sh -d "<device>" -b  # detached; returns only once the app is up
#
# Hot reload/restart: press r / R in this terminal, or from anywhere run
# bin/dev_reload.sh [r|R] (works even when the app was started in background).
#
# Output always lands in dev_data/flutter.log. dev_data/flutter.pid holds the flutter
# pid while the app is up, so `kill -0 $(cat dev_data/flutter.pid)` is the readiness
# check - flutter writes that file only after the app starts and removes it on exit.
#
# Desktop only: fixtures in dev_data/igc (gitignored - real coordinates) are seeded via
# XDG_DOCUMENTS_DIR into dev_data/app_documents. A device uses its own sandbox instead,
# so seeding is skipped there and --reset refuses rather than pretending to work.
#
# Android only: the phone's logcat ring is quietened and resized first, or the app's own
# startup lines age out of it within ~30 seconds (see tune_device_logging below).
# DEV_RUN_SKIP_LOG_TUNING=1 leaves the device's logging config untouched.
#
# Note: the 3D map needs Android/iOS - on desktop it shows a placeholder.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/the_paragliding_app"
DEV_DATA="$REPO_ROOT/dev_data"
SEED_IGC_DIR="${SEED_IGC_DIR:-$DEV_DATA/igc}"
# Only the most recent flights are seeded - a full archive takes minutes to
# import. Override with SEED_IGC_LIMIT=20, or 0 to seed everything.
SEED_IGC_LIMIT="${SEED_IGC_LIMIT:-8}"
APP_DOCUMENTS="$DEV_DATA/app_documents"
# On desktop the app stores its database alongside its documents (see main.dart)
DB_FILE="$APP_DOCUMENTS/FlightLog.db"
# Pre-existing databases from before that change
LEGACY_DB_FILE="$APP_DIR/.dart_tool/sqflite_common_ffi/databases/FlightLog.db"

reset=false
profile=false
background=false
device="linux"
passthrough=()
PID_FILE="$DEV_DATA/flutter.pid"
LOG_FILE="$DEV_DATA/flutter.log"
# The first Android build compiles from cold and can take minutes
ready_timeout="${DEV_RUN_READY_TIMEOUT:-300}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset)
      reset=true
      shift
      ;;
    --profile)
      profile=true
      shift
      ;;
    -b|--background)
      background=true
      shift
      ;;
    -d|--device)
      [[ -n "${2:-}" ]] || { echo "ERROR: $1 requires a device id" >&2; exit 1; }
      device="$2"
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
      passthrough+=("$1")
      shift
      ;;
  esac
done

# Only the Linux desktop build stores its data under dev_data; on a device the app
# uses its own sandbox, so seeding and --reset do not apply there.
is_desktop=false
[[ "$device" == "linux" ]] && is_desktop=true

# Make the phone's logcat usable before flutter starts writing to it.
#
# The Pixel thermal HAL logs one `I pixel-thermal:` line per sensor per poll: measured
# at 84.5 lines/s, 79% of the main buffer, leaving ~30s of retention in the 256 KiB
# default. That is short enough that the app's own startup lines are gone before you can
# read them - and it was long misread as adbd flooding the buffer. Silencing it and
# raising the ring measured 9.5 lines/s and ~65 min.
#
# None of this needs root, and it is all reversible (`setprop <name> ""`, or a reboot for
# the size). Set DEV_RUN_SKIP_LOG_TUNING=1 to leave the device alone - worth it if you
# are actually debugging thermal or USB behaviour, which is what these tags are for.
tune_device_logging() {
  local dev="$1"

  command -v adb >/dev/null 2>&1 || return 0

  # Only Android has logcat. `is_desktop` is false for `-d chrome` too, so testing for
  # a real adb transport is what keeps this from firing at the web build.
  adb devices | awk '$2 == "device" { print $1 }' | grep -qxF "$dev" || return 0

  # Both forms: persist.* survives reboot, the bare one is what an already-running HAL
  # picks up now. Never fail the run over log tuning - warn and carry on.
  local tag
  for tag in pixel-thermal libPixelUsbOverheat; do
    adb -s "$dev" shell setprop "persist.log.tag.$tag" S 2>/dev/null || true
    adb -s "$dev" shell setprop "log.tag.$tag" S 2>/dev/null || true
  done

  # -G resets on reboot, so this runs every launch. Raise only from a KiB-sized ring:
  # matching on the unit rather than parsing a number keeps a buffer someone deliberately
  # set larger from being shrunk back to 4 MiB.
  local size
  size="$(adb -s "$dev" shell logcat -g 2>/dev/null | grep '^main:' || true)"
  if [[ "$size" != *MiB* ]]; then
    adb -s "$dev" shell logcat -G 4M 2>/dev/null || true
  fi

  echo "Quietened pixel-thermal/libPixelUsbOverheat and sized the logcat ring for '$dev' (DEV_RUN_SKIP_LOG_TUNING=1 to skip)."
}

if $reset && ! $is_desktop; then
  cat >&2 <<EOF
ERROR: --reset only deletes host-side desktop state ($APP_DOCUMENTS).
The database inside the app on device '$device' is untouched by it, so this
would look like a reset without being one.

To clear the DEBUG app's data on the device, run this yourself:
  adb -s "$device" shell pm clear com.theparaglidingapp.debug

NEVER clear com.theparaglidingapp (no .debug suffix) - that is the production
install and it holds real flight data that exists nowhere else.
EOF
  exit 1
fi

if $reset; then
  # Guard against ever removing something outside dev_data
  case "$APP_DOCUMENTS" in
    "$DEV_DATA"/*) ;;
    *) echo "ERROR: refusing to delete $APP_DOCUMENTS (outside $DEV_DATA)" >&2; exit 1 ;;
  esac
  echo "Resetting dev state:"
  echo "  documents (incl. database): $APP_DOCUMENTS"
  rm -rf "$APP_DOCUMENTS"
  rm -f "$LEGACY_DB_FILE"
fi

# Seeding only makes sense on desktop: SEED_IGC_DIR is a host path, and the app on a
# device cannot read it. Leaving the define unset also keeps DevSeed.isConfigured false,
# so the splash does not claim "Preparing dev database" on a device.
seed_args=()
if $is_desktop; then
  mkdir -p "$APP_DOCUMENTS" "$SEED_IGC_DIR"

  igc_count=$(find "$SEED_IGC_DIR" -maxdepth 1 -iname '*.igc' | wc -l)
  if [[ "$igc_count" -eq 0 ]]; then
    echo "WARNING: no .igc files in $SEED_IGC_DIR - the app will start with an empty log." >&2
    echo "         Copy ~10 real flights there to seed the database." >&2
  elif [[ "$SEED_IGC_LIMIT" -le 0 || "$SEED_IGC_LIMIT" -ge "$igc_count" ]]; then
    echo "Seeding from all $igc_count IGC file(s) in $SEED_IGC_DIR (skipped if flights already exist)"
  else
    echo "Seeding the $SEED_IGC_LIMIT most recent of $igc_count IGC file(s) in $SEED_IGC_DIR (skipped if flights already exist)"
  fi

  # path_provider_linux resolves getApplicationDocumentsDirectory() via xdg-user-dir,
  # which honours this variable
  export XDG_DOCUMENTS_DIR="$APP_DOCUMENTS"

  seed_args=(
    --dart-define=SEED_IGC_DIR="$SEED_IGC_DIR"
    --dart-define=SEED_IGC_LIMIT="$SEED_IGC_LIMIT"
  )
else
  echo "Device '$device' is not the Linux desktop: dev seeding is off, and the app uses whatever data is already on the device."
  # Before flutter starts, so the app's own startup lines land in a ring that keeps them.
  [[ -n "${DEV_RUN_SKIP_LOG_TUNING:-}" ]] || tune_device_logging "$device"
fi

mode_args=()
if $profile; then
  mode_args+=(--profile)
  echo "Profile build: hot reload is unavailable, and startup includes an AOT compile."
fi

cd "$APP_DIR"

# API keys come from env.json (gitignored). Without it the app still runs, but
# FFVL weather, OpenAIP overlays and Cesium 3D are all unconfigured.
env_file_args=()
if [[ -f env.json ]]; then
  env_file_args+=(--dart-define-from-file=env.json)
else
  echo "WARNING: no env.json - API keys will be unset. Copy env.example.json and fill it in (see README_API_KEYS.md)." >&2
fi

# flutter writes the pid file only once the app is actually up on the device (it is
# written by registerSignalHandlers, which runs after appStarted) and removes it on
# exit. So a live pid here means "running and accepting SIGUSR1" - that is the whole
# readiness check, and unlike a scraped status string it cannot be wrong.
if [[ -s "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "ERROR: already running (flutter pid $(cat "$PID_FILE"))." >&2
  echo "       Stop it first: kill \$(cat $PID_FILE)" >&2
  exit 1
fi
rm -f "$PID_FILE"

run_args=(
  run -d "$device"
  --pid-file "$PID_FILE"
  ${env_file_args[@]+"${env_file_args[@]}"}
  ${seed_args[@]+"${seed_args[@]}"}
  ${mode_args[@]+"${mode_args[@]}"}
  ${passthrough[@]+"${passthrough[@]}"}
)

if ! $background; then
  # tee rather than exec, so there is always a log to read afterwards. stdin is left
  # alone, so the interactive r / R keys still work.
  flutter "${run_args[@]}" 2>&1 | tee "$LOG_FILE"
  exit
fi

# setsid, not nohup: nohup only ignores SIGHUP, but a caller that kills its whole
# process group (as agent tooling does on timeout) would still take flutter with it.
# A separate session survives both that and the launching shell exiting.
setsid flutter "${run_args[@]}" >"$LOG_FILE" 2>&1 </dev/null &
launcher=$!

# A log that stops silently looks exactly like a log with nothing to report - that is
# how a dead session got read as "the app was never touched". Flutter removes the pid
# file on exit, but that signal lives in a different file from the log being read, so
# stamp the end into the log itself. Detached, so it outlives this script.
#
# On a device the app usually keeps running after flutter detaches, so the marker says
# where the log stops, not that the app stopped - use bin/dev_logs.sh from there.
#
# The guards below exist for races that are awkward to hit by hand. To re-verify after
# changing this, extract the watcher body and drive it against fake pid/log files:
#
#   awk "/^setsid bash -c '\$/{f=1;next} f&&/^' _ /{f=0} f" bin/dev_run.sh >/tmp/w.sh
#   sleep 60 & echo $! >/tmp/t.pid; echo one >/tmp/t.log
#   bash /tmp/w.sh /tmp/t.pid /tmp/t.log 10 $! &
#
# then kill the sleep to see the marker land; or leave a stale pid file and truncate
# the log first to confirm it stays quiet. Strip the guard lines to watch it fail.
setsid bash -c '
  pid_file=$1 log_file=$2 wait_ready=$3 launcher=$4
  deadline=$((SECONDS + wait_ready))
  while (( SECONDS < deadline )); do
    [[ -s "$pid_file" ]] && break
    # Give up with the launcher, mirroring the readiness loop below. Without this a
    # failed build left this watcher polling for the whole ready timeout; a fix-and-
    # retry inside that window would arm it against the *new* session, running
    # alongside the watcher that session spawned, and both would stamp the marker.
    #
    # No apostrophes in here - this whole block is inside a single-quoted bash -c.
    kill -0 "$launcher" 2>/dev/null || exit 0
    sleep 1
  done
  # Never became ready - the launcher reports that case itself, so stay quiet.
  [[ -s "$pid_file" ]] || exit 0
  pid=$(cat "$pid_file")
  # Size at arm time, to detect a later run truncating the log out from under us.
  armed_size=$(stat -c %s "$log_file" 2>/dev/null || echo 0)

  while kill -0 "$pid" 2>/dev/null; do sleep 2; done

  # A crash that skips flutter cleanup leaves a stale pid file, so a restart within
  # the poll interval gets past the already-running guard, truncates this log and
  # claims it. Stamping "exited" then would brand a live session dead - the same
  # confusion this marker exists to prevent, only inverted. Two ways to spot it:
  # the pid file now names a different process, or the log shrank.
  now_pid=$(cat "$pid_file" 2>/dev/null || true)
  [[ -n "$now_pid" && "$now_pid" != "$pid" ]] && exit 0
  now_size=$(stat -c %s "$log_file" 2>/dev/null || echo 0)
  (( now_size < armed_size )) && exit 0

  printf -- "--- flutter exited %s - log ends here; the app may still be running on the device ---\n" \
    "$(date "+%Y-%m-%d %H:%M:%S")" >>"$log_file"
' _ "$PID_FILE" "$LOG_FILE" "$ready_timeout" "$launcher" >/dev/null 2>&1 </dev/null &

echo "Starting on '$device' in the background; log: $LOG_FILE"
deadline=$((SECONDS + ready_timeout))
while :; do
  if [[ -s "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Ready (flutter pid $(cat "$PID_FILE")). Hot reload with: bin/dev_reload.sh [r|R]"
    exit 0
  fi
  if ! kill -0 "$launcher" 2>/dev/null; then
    echo "ERROR: flutter exited before the app was ready. Last 40 lines of $LOG_FILE:" >&2
    tail -n 40 "$LOG_FILE" >&2
    exit 1
  fi
  if (( SECONDS >= deadline )); then
    echo "ERROR: still not ready after ${ready_timeout}s. Last 20 lines of $LOG_FILE:" >&2
    tail -n 20 "$LOG_FILE" >&2
    exit 1
  fi
  sleep 2
done
