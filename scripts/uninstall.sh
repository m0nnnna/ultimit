#!/bin/sh
# Remove what scripts/install.sh put on this computer and give the login back to GDM (if it is
# still installed). Users' own settings (~/.config/ultimit, keyrings, files) are left alone; the
# apps from distro/ (Steam, Flatpaks, ...) stay too.
#
#   scripts/uninstall.sh          show what would be removed
#   scripts/uninstall.sh --yes    do it (sudo)
#
# If the Ultimit login screen ever doesn't come up: press Ctrl+Alt+F3, log in on the text console
# and run this script (or: sudo systemctl disable greetd && sudo systemctl enable gdm3 && sudo reboot).
set -e
P=/opt/ultimit
echo "Would remove: $P, /usr/share/wayland-sessions/ultimit.desktop, /usr/share/fonts/truetype/ultimit,"
echo "  the ultimit-* commands in /usr/local/bin, Ultimit's entries in /usr/share/applications,"
echo "  pam_oo7 from /etc/pam.d/greetd, the Ultimit helpers and polkit policies,"
echo "  and switch the login screen back to GDM$(command -v gdm3 >/dev/null || echo ', reinstalling Ubuntu'"'"'s desktop (GNOME, GDM) first since it was removed: needs internet')."
[ "${1:-}" = --yes ] || { echo "Dry run. Run with --yes to do it."; exit 0; }
# GNOME was removed by the install: bring Ubuntu's desktop back so there is a login screen.
if ! command -v gdm3 >/dev/null; then
	sudo apt-get update -q && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-desktop-minimal gdm3
fi
sudo sh -e -c '
	P=$1
	if command -v gdm3 >/dev/null; then
		systemctl disable greetd 2>/dev/null || true
		systemctl enable --force gdm3
		echo /usr/sbin/gdm3 >/etc/X11/default-display-manager
	fi
	[ -f /etc/greetd/config.toml.before-ultimit ] && mv /etc/greetd/config.toml.before-ultimit /etc/greetd/config.toml
	sed -i "/# Ultimit: unlock the oo7 keyring/,+2d" /etc/pam.d/greetd 2>/dev/null || true
	systemctl disable ultimit-firstboot.service 2>/dev/null || true
	rm -f /etc/systemd/system/ultimit-firstboot.service
	rm -f /usr/lib/x86_64-linux-gnu/security/pam_oo7.so /usr/share/wayland-sessions/ultimit.desktop
	rm -rf /usr/share/fonts/truetype/ultimit /var/lib/ultimit-greeter
	for l in /usr/local/bin/ultimit*; do [ "$(readlink "$l" 2>/dev/null | cut -c1-${#P})" = "$P" ] && rm -f "$l"; done
	for d in "$P"/shell/apps/*/ultimit-*.desktop; do rm -f "/usr/share/applications/$(basename "$d")"; done
	# NekoMail (system-install.sh); mail stays in each home, ~/.config/nekomail, ~/.local/share/nekomail
	if [ "$(readlink /usr/local/bin/nekomail 2>/dev/null | cut -c1-${#P})" = "$P" ]; then
		rm -f /usr/local/bin/nekomail /usr/share/applications/nekomail.desktop /usr/lib/systemd/user/nekomail.service \
			/usr/share/icons/hicolor/scalable/apps/nekomail.svg /usr/share/icons/hicolor/192x192/apps/nekomail.png \
			/usr/share/icons/hicolor/512x512/apps/nekomail.png
	fi
	if [ -d "$P/distro/system" ]; then
		cd "$P/distro/system" && find . -type f | while read -r f; do rm -f "/$f"; done
	fi
	rm -rf "$P"
	fc-cache -f >/dev/null 2>&1 || true
' sh "$P"
echo "Ultimit removed. Reboot to get the previous login screen back."
