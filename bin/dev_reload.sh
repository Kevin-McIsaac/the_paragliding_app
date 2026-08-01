#!/usr/bin/env bash
#
# Hot reload or restart an app started with bin/dev_run.sh, without needing the
# terminal it is running in. The flutter tool listens for:
#   SIGUSR1 -> hot reload    SIGUSR2 -> hot restart
#
#   bin/dev_reload.sh        # hot reload (default)
#   bin/dev_reload.sh R      # hot restart - needed after changing main()/initState
#
# Hot reload does not apply to profile or release builds.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$REPO_ROOT/dev_data/flutter.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "ERROR: $PID_FILE not found - is the app running via bin/dev_run.sh?" >&2
  exit 1
fi

pid="$(cat "$PID_FILE")"
if ! kill -0 "$pid" 2>/dev/null; then
  echo "ERROR: no process $pid - the app is not running (stale pid file)" >&2
  exit 1
fi

case "${1:-r}" in
  r|reload)
    kill -USR1 "$pid"
    echo "Hot reload sent to $pid"
    ;;
  R|restart)
    kill -USR2 "$pid"
    echo "Hot restart sent to $pid"
    ;;
  *)
    echo "ERROR: expected 'r' (reload) or 'R' (restart), got '$1'" >&2
    exit 1
    ;;
esac
