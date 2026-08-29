#!/usr/bin/env bash
#
# Keep the in-app user manual in sync with its source.
#
#   docs/user/User_Manual.md                              <- the source; edit this
#   the_paragliding_app/assets/documentation/user_manual.md  <- generated; ships in the app
#
#   bin/sync_user_manual.sh           # copy source -> asset
#   bin/sync_user_manual.sh --check   # exit 1 if they differ (used by CI)
#
# The asset is committed rather than generated at build time so a checkout builds
# without running anything first. --check in CI is what stops the two drifting: they
# had diverged by 256 lines and about six months before this script existed, and the
# copy users actually read was the older one.
#
# Flutter cannot bundle an asset from outside its package directory, which is why this
# is a copy rather than a symlink or a pubspec path.
#
# HTML comments are stripped on the way across. The source carries a maintainer note at
# the top telling you to edit it rather than the asset; that note must not reach users.
# The manual is rendered with flutter_markdown_plus's Markdown widget, which does not
# promise to hide raw HTML - rather than depend on that, don't ship the comment.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$REPO_ROOT/docs/user/User_Manual.md"
ASSET="$REPO_ROOT/the_paragliding_app/assets/documentation/user_manual.md"

if [[ ! -f "$SOURCE" ]]; then
  echo "ERROR: source manual not found at $SOURCE" >&2
  exit 1
fi

# Source, minus HTML comment blocks and any blank lines they leave behind.
render_source() {
  perl -0777 -pe 's/<!--.*?-->\n*//gs' "$SOURCE"
}

if [[ "${1:-}" == "--check" ]]; then
  if render_source | diff -q - "$ASSET" >/dev/null 2>&1; then
    echo "user manual in sync"
    exit 0
  fi
  echo "ERROR: the shipped user manual differs from its source." >&2
  echo "  source: $SOURCE" >&2
  echo "  asset:  $ASSET" >&2
  echo "Edit the source, then run: bin/sync_user_manual.sh" >&2
  echo >&2
  render_source | diff - "$ASSET" | head -40 >&2
  exit 1
fi

render_source > "$ASSET"
echo "synced $ASSET <- $SOURCE"
