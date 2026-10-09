#!/bin/sh
# Adds "Ultimit" to the login screen's session list. The session runs the
# compositor and shell straight from this checkout, so rebuilding here is
# enough to update it. Remove with: sudo rm /usr/share/wayland-sessions/ultimit.desktop
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SESSION="$ROOT/session/ultimit-session"
[ -x "$ROOT/compositor/build/ultimit" ] || { echo "Build first: scripts/run-nested.sh"; exit 1; }
sed "s|@SESSION@|$SESSION|g" "$ROOT/session/ultimit.desktop" | \
	sudo tee /usr/share/wayland-sessions/ultimit.desktop >/dev/null
echo "Installed. Log out, click the gear on the login screen and pick Ultimit."
