#!/bin/sh
# Ultimit's browser: Ungoogled Chromium (Flathub; it has no maintained
# Ubuntu packages). Removes the Chromium and Firefox snaps and Ubuntu's
# firefox transitional package, sets Ungoogled Chromium as the default
# browser, makes it use Ultimit's theme and titlebar, and gives it
# spell-check dictionaries.
#
# Used on this machine and by the ISO build (distro/). Needs sudo.
set -e
APP=io.github.ungoogled_software.ungoogled_chromium

echo "== Removing the Chromium and Firefox snaps (and their data)"
for s in chromium firefox; do
	snap list "$s" >/dev/null 2>&1 && sudo snap remove --purge "$s"
done
dpkg-query -W -f='${Status}' firefox 2>/dev/null | grep -q "install ok installed" && sudo apt-get purge -y firefox
# Ubuntu's firefox/chromium debs only install the snap: keep apt from
# pulling them back in.
sudo tee /etc/apt/preferences.d/ultimit-no-browser-snaps >/dev/null <<'PIN'
# Ultimit uses Ungoogled Chromium from Flathub.
Package: firefox chromium-browser
Pin: release *
Pin-Priority: -1
PIN

echo "== Flatpak + Flathub"
sudo apt-get install -y flatpak
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "== Ungoogled Chromium"
sudo flatpak install -y --noninteractive flathub "$APP"

echo "== Default browser"
DESKTOP="$APP.desktop"
xdg-settings set default-web-browser "$DESKTOP" || true
for t in x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml; do
	xdg-mime default "$DESKTOP" "$t"
done

# Ultimit's GTK theme and the system (Ultimit) titlebar instead of Chromium's
# own frame, for every profile (session/ultimit-flatpak-theme, also run at
# each login).
"$(dirname "$(readlink -f "$0")")/../session/ultimit-flatpak-theme" || true
# Spell-check dictionaries: Ungoogled Chromium blocks its own download of them
# (session/ultimit-spellcheck, also run at each login).
"$(dirname "$(readlink -f "$0")")/../session/ultimit-spellcheck" || true
echo "Done: $(xdg-settings get default-web-browser 2>/dev/null)"
