#!/bin/sh
# Restart the running Ultimit login session so a new compositor build takes
# effect. With autologin (scripts/setup-autologin.sh) it comes straight back
# and autostart reopens Claude. Everything open in the session closes.
set -e
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/ultimit-session.pid"
pid=$(cat "$PIDFILE" 2>/dev/null) || { echo "no Ultimit session running"; exit 1; }
[ "$(cat /proc/"$pid"/comm 2>/dev/null)" = ultimit ] || { echo "stale pid file"; exit 1; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# Refuse to restart into a broken build.
ninja -C "$ROOT/compositor/build" -j4 >/dev/null
echo "Restarting Ultimit (pid $pid) in ${1:-3}s..."
sleep "${1:-3}"
kill -TERM "$pid"
