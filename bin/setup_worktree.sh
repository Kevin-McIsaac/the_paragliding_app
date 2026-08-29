#!/usr/bin/env bash
#
# Bootstrap a freshly created worktree with the gitignored files it needs to
# build and run: env.json (API keys), android/key.properties (release
# signing), and `flutter pub get`. None of these come from `git worktree
# add` since they are gitignored - see the `worktree` skill for why skipping
# this fails silently instead of loudly.
#
#   bin/setup_worktree.sh
#
# Run from inside the new worktree, from anywhere under its checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/the_paragliding_app"
MAIN="$(git -C "$REPO_ROOT" worktree list --porcelain | awk '/^worktree/{print $2; exit}')"
MAIN_APP_DIR="$MAIN/the_paragliding_app"

if [[ "$MAIN" == "$REPO_ROOT" ]]; then
  echo "Already in the main checkout ($REPO_ROOT) - nothing to bootstrap." >&2
  exit 0
fi

mkdir -p "$REPO_ROOT/dev_data"

copy_if_source_exists() {
  local src="$1" dest="$2"
  if [[ -f "$dest" ]]; then
    echo "skip $dest (already present)"
  elif [[ -f "$src" ]]; then
    cp "$src" "$dest"
    echo "copied $dest <- $src"
  else
    echo "WARNING: $src not found in main checkout - $dest not created" >&2
  fi
}

copy_if_source_exists "$MAIN_APP_DIR/env.json" "$APP_DIR/env.json"
copy_if_source_exists "$MAIN_APP_DIR/android/key.properties" "$APP_DIR/android/key.properties"

(cd "$APP_DIR" && flutter pub get)

echo "Worktree bootstrapped. Re-seed dev_data/igc only if this task needs the app to actually run."
