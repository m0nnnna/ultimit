#!/bin/sh
# Adds "Ultimit" to the login screen's session list.
#
# The login screen runs as the gdm user, which can't read inside a private
# home folder, so it would hide a session whose launcher lives there. We put
# a tiny launcher in /usr/local/bin that hands off to this checkout; the
# session still runs the compositor and shell from here, so rebuilding is
# enough to update it.
#
# Remove with:
#   sudo rm /usr/share/wayland-sessions/ultimit.desktop /usr/local/bin/ultimit-session
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[ -x "$ROOT/compositor/build/ultimit" ] || { echo "Build first: scripts/run-nested.sh"; exit 1; }

LAUNCHER=/usr/local/bin/ultimit-session
printf '#!/bin/sh\nexec "%s/session/ultimit-session" "$@"\n' "$ROOT" | sudo tee "$LAUNCHER" >/dev/null
sudo chmod 755 "$LAUNCHER"
sed "s|@SESSION@|$LAUNCHER|g" "$ROOT/session/ultimit.desktop" | \
	sudo tee /usr/share/wayland-sessions/ultimit.desktop >/dev/null
echo "Installed. Log out, click your name, then the gear (bottom right) and pick Ultimit."
