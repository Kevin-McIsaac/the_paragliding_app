#!/usr/bin/env bash
#
# Run the app on Linux desktop with dev fixtures seeded from real IGC files.
#
#   bin/dev_run.sh              # run, seeding on first launch (empty database)
#   bin/dev_run.sh --reset      # wipe dev database + app documents, then run
#   bin/dev_run.sh --profile    # profile build, for timing without debug overhead
#   bin/dev_run.sh -d chrome    # any other flutter device
#
# Hot reload/restart: press r / R in this terminal, or from anywhere run
# bin/dev_reload.sh [r|R] (works even when the app was started in background).
#
# Fixtures live in dev_data/igc (gitignored - they contain real coordinates).
# All app state is redirected into dev_data/app_documents via XDG_DOCUMENTS_DIR
# so nothing lands in your home directory and --reset is safe.
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
device="linux"
passthrough=()
PID_FILE="$DEV_DATA/flutter.pid"

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
    -d|--device)
      [[ -n "${2:-}" ]] || { echo "ERROR: $1 requires a device id" >&2; exit 1; }
      device="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      passthrough+=("$1")
      shift
      ;;
  esac
done

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

exec flutter run -d "$device" \
  --pid-file "$PID_FILE" \
  ${env_file_args[@]+"${env_file_args[@]}"} \
  --dart-define=SEED_IGC_DIR="$SEED_IGC_DIR" \
  --dart-define=SEED_IGC_LIMIT="$SEED_IGC_LIMIT" \
  ${mode_args[@]+"${mode_args[@]}"} \
  ${passthrough[@]+"${passthrough[@]}"}
