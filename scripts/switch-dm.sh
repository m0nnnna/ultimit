#!/bin/sh
# Choose the login screen.
#   scripts/switch-dm.sh greetd [--autologin]   Ultimit greeter (greetd)
#   scripts/switch-dm.sh gdm                    back to GDM
# Takes effect at the next boot (switching live would end your session).
#
# If the Ultimit greeter ever fails to come up: press Ctrl+Alt+F3, log in on
# the text console and run:  sudo systemctl disable greetd && sudo systemctl enable gdm3 && sudo reboot
set -e
USER_NAME=${SUDO_USER:-$USER}
case "$1" in
greetd)
	[ -x /opt/ultimit/libexec/ultimit-greeter-session ] || { echo "Run scripts/install-system.sh first"; exit 1; }
	GREETER_USER=$(getent passwd _greetd >/dev/null && echo _greetd || echo greeter)
	AUTO=""
	if [ "$2" = --autologin ]; then
		# greetd starts this once per greetd start; scripts/restart-session.sh
		# restarts greetd so a dev restart logs straight back in.
		AUTO=$(printf '\n[initial_session]\ncommand = "/usr/local/bin/ultimit-session"\nuser = "%s"\n' "$USER_NAME")
	fi
	sudo sh -e <<SUDO
[ -f /etc/greetd/config.toml ] && cp -n /etc/greetd/config.toml /etc/greetd/config.toml.ubuntu-default
cat >/etc/greetd/config.toml <<CONF
# Written by Ultimit scripts/switch-dm.sh
[terminal]
vt = 1

[default_session]
command = "/opt/ultimit/libexec/ultimit-greeter-session"
user = "$GREETER_USER"
$AUTO
CONF
chown "$GREETER_USER" /var/lib/ultimit-greeter 2>/dev/null || true
# Let $USER_NAME restart the login screen (dev restarts) without a password.
cat >/etc/polkit-1/rules.d/50-ultimit-greetd.rules <<RULE
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        action.lookup("unit") == "greetd.service" &&
        action.lookup("verb") == "restart" &&
        subject.user == "$USER_NAME") {
        return polkit.Result.YES;
    }
});
RULE
systemctl disable gdm3
systemctl enable greetd
SUDO
	echo "greetd is the login screen from the next boot."
	;;
gdm)
	sudo sh -e <<'SUDO'
systemctl disable greetd
systemctl enable gdm3
rm -f /etc/polkit-1/rules.d/50-ultimit-greetd.rules
SUDO
	echo "GDM is the login screen from the next boot."
	;;
*)
	sed -n '2,9p' "$0"
	exit 1
	;;
esac
