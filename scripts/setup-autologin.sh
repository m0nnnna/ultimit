#!/bin/sh
# Dev convenience: log straight into Ultimit with no password at boot and
# after logout, so scripts/restart-session.sh is a full round trip.
# Undo with: scripts/setup-autologin.sh --off
set -e
USER_NAME=${SUDO_USER:-$USER}
CONF=/etc/gdm3/custom.conf
ACCT=/var/lib/AccountsService/users/$USER_NAME
if [ "$1" = --off ]; then
	sudo sed -i '/^AutomaticLogin\|^TimedLogin/d' "$CONF"
	echo "Autologin off."
	exit 0
fi
sudo cp -n "$CONF" "$CONF.ultimit-backup" || true
sudo sed -i '/^AutomaticLogin\|^TimedLogin/d' "$CONF"
# AutomaticLogin covers boot; TimedLogin re-logs in when the greeter
# reappears after a logout or a session restart.
sudo sed -i "/^\[daemon\]/a AutomaticLoginEnable=true\nAutomaticLogin=$USER_NAME\nTimedLoginEnable=true\nTimedLogin=$USER_NAME\nTimedLoginDelay=1" "$CONF"
# Make Ultimit the default session for this user.
if sudo test -f "$ACCT"; then
	sudo sed -i '/^Session=/d; /^XSession=/d' "$ACCT"
	sudo sed -i "/^\[User\]/a Session=ultimit" "$ACCT"
else
	printf '[User]\nSession=ultimit\nSystemAccount=false\n' | sudo tee "$ACCT" >/dev/null
fi
mkdir -p "$HOME/.config/autostart"
cp "$(cd "$(dirname "$0")/.." && pwd)/session/claude-autostart.desktop" "$HOME/.config/autostart/ultimit-claude.desktop"
echo "Autologin into Ultimit enabled for $USER_NAME; Claude reopens on login."
sudo grep -A6 '^\[daemon\]' "$CONF"
