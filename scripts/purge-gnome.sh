#!/bin/bash
# Phase 4: remove the GNOME desktop from this Ubuntu install, keeping GTK,
# GLib, dconf and everything Ultimit or games rely on.
#
#   scripts/purge-gnome.sh          dry run: print what would go and what is kept
#   scripts/purge-gnome.sh --yes    do it (sudo)
#
# Purging ubuntu-desktop-minimal makes ~400 packages "automatically
# installed and unused", including xwayland, bluez, udisks2, pipewire-alsa,
# power-profiles-daemon and switcheroo-control. So before purging, every
# autoremove candidate that is not a GNOME leftover is marked manually
# installed; autoremove then only takes GNOME leftovers.
#
# Rollback: sudo apt install ubuntu-desktop-minimal gdm3 (then
# scripts/switch-dm.sh gdm). The lists used are saved next to the log.
set -euo pipefail
export LC_ALL=C   # sort and comm must agree on order

PURGE=(
	ubuntu-desktop-minimal ubuntu-session gdm3
	gnome-shell gnome-shell-ubuntu-extensions yaru-theme-gnome-shell
	gnome-session-bin gnome-settings-daemon gnome-control-center
	gnome-initial-setup gnome-keyring seahorse gnome-online-accounts
	evolution-data-server xdg-desktop-portal-gnome
	gvfs gvfs-backends gvfs-daemons gvfs-fuse
	nautilus gnome-text-editor gnome-calculator gnome-terminal ptyxis
	papers loupe gnome-disk-utility gnome-logs gnome-clocks gnome-characters
)

# Autoremove candidates that are GNOME leftovers (removed). Everything else
# that autoremove would take is kept.
GNOME_RX='^(gvfs-|libgoa|libebook|libedata|libedataserver|evolution-data-server-common|libecal|libebackend|libcamel|gir1\.2-(mutter|gnome|gdm|gweather|gdesktopenums|gmenu|webkit2|javascriptcoregtk|wnck|vte|gck|gcr)|libgnome-|libmutter|gnome-|mutter-common|nautilus-|libnautilus|gjs$|libgjs|libmozjs|papers-common|libpps|baobab|libgdm|language-selector-gnome|libgweather|geocode-glib|libgeocode|tecla|localsearch|tinysparql|libmalcontent|libpanel|libspelling|libgtksourceview-5|libwnck|libvte-2.91-gtk4|rygel|librygel|libgupnp|sysprof|libsysprof|whoopsie|libwhoopsie|ubuntu-docs|libunity|libdee|apport-gtk|update-manager|update-notifier$|ubuntu-release-upgrader-gtk|python3-aptdaemon\.gtk3widgets|libgsound|libgnome-qr|libglycin-gtk4|libcolord-gtk4|libportal-gtk4|libmsgraph|librest|libinsights|ubuntu-insights|ubuntu-report|libwebkit2gtk|libjavascriptcoregtk|gst-(audio|video)-thumbnailer|libgtop|libgxps|libphonenumber|libpam-gnome-keyring)'
# Matched above but kept: not the GNOME desktop, and useful without it.
KEEP_ANYWAY='^(gnome-themes-extra|gnome-accessibility-themes|network-manager-(openvpn|pptp)-gnome|libnma|gir1\.2-nma4)'

installed=()
for p in "${PURGE[@]}"; do
	dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" && installed+=("$p")
done
[ ${#installed[@]} -gt 0 ] || { echo "Nothing from the GNOME list is installed."; exit 0; }

out=${XDG_STATE_HOME:-$HOME/.local/state}/ultimit/purge-$(date +%Y%m%d-%H%M%S)
mkdir -p "$out"
apt-get -s purge --autoremove "${installed[@]}" 2>/dev/null | awk '/^Purg/ {print $2}' | sort >"$out/all.txt"
printf '%s\n' "${installed[@]}" | sort >"$out/purge.txt"
comm -23 "$out/all.txt" "$out/purge.txt" >"$out/autoremove.txt"
grep -E "$GNOME_RX" "$out/autoremove.txt" | grep -vE "$KEEP_ANYWAY" >"$out/leftovers.txt" || true
comm -23 "$out/autoremove.txt" "$out/leftovers.txt" >"$out/keep.txt"

echo "== Purge (${#installed[@]}):"; tr '\n' ' ' <"$out/purge.txt" | fold -s -w 100; echo
echo "== GNOME leftovers also removed ($(wc -l <"$out/leftovers.txt")):"; tr '\n' ' ' <"$out/leftovers.txt" | fold -s -w 100; echo
echo "== Kept, marked manually installed ($(wc -l <"$out/keep.txt")):"; tr '\n' ' ' <"$out/keep.txt" | fold -s -w 100; echo
echo "Lists saved in $out"

if [ "${1:-}" != "--yes" ]; then
	echo; echo "Dry run. Run with --yes to do it."
	exit 0
fi

# Empty on a re-run: an earlier run already marked them.
[ -s "$out/keep.txt" ] && sudo apt-mark manual $(cat "$out/keep.txt") >/dev/null
# Check the result before touching anything: nothing outside purge +
# leftovers may go. (Fewer is fine: some leftovers are still needed by a
# kept package and stay.)
apt-get -s purge --autoremove "${installed[@]}" 2>/dev/null | awk '/^Purg/ {print $2}' | sort >"$out/final.txt"
sort -u "$out/purge.txt" "$out/leftovers.txt" >"$out/expected.txt"
comm -23 "$out/final.txt" "$out/expected.txt" >"$out/unexpected.txt"
if [ -s "$out/unexpected.txt" ]; then
	echo "Unexpected removals; stopping before anything is removed:"
	cat "$out/unexpected.txt"
	exit 1
fi
echo "Removing $(wc -l <"$out/final.txt") packages ($(comm -13 "$out/final.txt" "$out/expected.txt" | wc -l) leftovers stay as dependencies of kept packages)."
sudo apt-get purge --autoremove -y "${installed[@]}" 2>&1 | tee "$out/apt.log"
echo "Done. Reboot to finish (log: $out/apt.log)."
