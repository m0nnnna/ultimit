#!/bin/bash
# Install what an Ultimit system ships, from the lists in distro/: apt
# packages (with 32-bit support for Wine and Steam), pinned .debs from outside
# the archive (umu-launcher), Flatpak with the Flathub remote and its apps
# (Ungoogled Chromium, ProtonPlus), and DXVK.
#
#   scripts/install-apps.sh          dry run: list what is missing
#   scripts/install-apps.sh --yes    install it (sudo)
#
# Safe to re-run: only missing pieces are installed. Steam's own client
# (~300 MB) downloads on each user's first launch, as on any distro.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FLATHUB=https://dl.flathub.org/repo/flathub.flatpakrepo

# ULTIMIT_SKIP_PACKAGES="a b": leave those out (test machines; scripts/install.sh passes it on).
# ULTIMIT_APPS_ONLY="a b": only these (an update installs what its release added to the lists,
# scripts/system-install.sh --apps-new); DXVK is then left alone.
only() { if [ -n "${ULTIMIT_APPS_ONLY:-}" ]; then grep -xF -f <(printf '%s\n' $ULTIMIT_APPS_ONLY) || true; else cat; fi; }
list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep -v '^$' | grep -vxF -f <(printf '%s\n' ${ULTIMIT_SKIP_PACKAGES:-} "") | only || true; }

# Ubuntu's own apt jobs (the daily update check, unattended-upgrades) often run right after boot,
# when the first-boot install runs too: wait for them rather than fail on apt's lock.
wait_apt() {
	local i
	for i in $(seq 360); do
		# (unattended-upgrade-shutdown idles all the time; only the updater itself counts)
		pgrep -x 'apt|apt-get|aptd|dpkg' >/dev/null || pgrep -f '^/usr/bin/python3 /usr/bin/unattended-upgrade( |$)' >/dev/null || return 0
		[ "$i" = 1 ] && echo "== Waiting for another package install to finish..."
		sleep 5
	done
}
APT_WAIT=(-o DPkg::Lock::Timeout=600)

installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

need_i386=false
dpkg --print-foreign-architectures | grep -qx i386 || need_i386=true

missing_apt=()
for p in $(list "$ROOT/distro/packages-install.txt"); do
	installed "$p" || missing_apt+=("$p")
done

missing_debs=()
while read -r pkg url sum; do
	[ -z "$(echo "$pkg" | only)" ] && continue
	installed "$pkg" || missing_debs+=("$pkg $url $sum")
done < <(sed -e 's/#.*//' "$ROOT/distro/debs.txt" | grep -v '^[[:space:]]*$')

have_flathub=false
command -v flatpak >/dev/null && flatpak remotes --system --columns=name | grep -qx flathub && have_flathub=true
missing_flatpak=()
for app in $(list "$ROOT/distro/flatpaks.txt"); do
	command -v flatpak >/dev/null && flatpak info --system "$app" >/dev/null 2>&1 || missing_flatpak+=("$app")
done

have_dxvk=false
[ -e /opt/ultimit/dxvk/current/x32/d3d9.dll ] || [ -n "${ULTIMIT_APPS_ONLY:-}" ] && have_dxvk=true

echo "== 32-bit (i386) architecture: $($need_i386 && echo "to enable" || echo enabled)"
echo "== apt packages missing (${#missing_apt[@]}): ${missing_apt[*]:-none}"
echo "== pinned .debs missing (${#missing_debs[@]}): $(for d in "${missing_debs[@]}"; do printf "%s " "${d%% *}"; done; [ ${#missing_debs[@]} -gt 0 ] || echo none)"
echo "== Flathub remote: $($have_flathub && echo present || echo "to add")"
echo "== Flatpaks missing (${#missing_flatpak[@]}): ${missing_flatpak[*]:-none}"
echo "== DXVK in /opt/ultimit/dxvk: $($have_dxvk && echo present || echo "to install")"

if [ "${1:-}" != "--yes" ]; then
	echo; echo "Dry run. Run with --yes to install."
	exit 0
fi

if $need_i386; then
	sudo dpkg --add-architecture i386
fi
if $need_i386 || [ ${#missing_apt[@]} -gt 0 ]; then
	wait_apt; sudo apt-get "${APT_WAIT[@]}" update
fi
# Steam's package asks you to accept Valve's licence: it gets the terminal to itself (output may be
# going through a log), everything else installs without questions.
interactive=() quiet=()
for p in "${missing_apt[@]}"; do
	case "$p" in steam-installer) interactive+=("$p") ;; *) quiet+=("$p") ;; esac
done
# DKMS modules (the virtual camera) are built for the running kernel: its headers must be there.
if printf '%s\n' "${quiet[@]}" | grep -q -- '-dkms$' && ! installed "linux-headers-$(uname -r)" \
		&& apt-cache show "linux-headers-$(uname -r)" >/dev/null 2>&1; then
	quiet+=("linux-headers-$(uname -r)")
fi
if [ ${#quiet[@]} -gt 0 ]; then
	wait_apt; sudo DEBIAN_FRONTEND=noninteractive apt-get "${APT_WAIT[@]}" install -y "${quiet[@]}"
fi
if [ ${#interactive[@]} -gt 0 ]; then
	if [ -r /dev/tty ] && [ -w /dev/tty ] && (exec </dev/tty) 2>/dev/null; then
		echo "== Steam: accept Valve's licence in the dialog to install it"
		wait_apt; sudo apt-get "${APT_WAIT[@]}" install -y "${interactive[@]}" </dev/tty >/dev/tty 2>&1 \
			|| echo "!! Steam wasn't installed (licence not accepted?). Later: sudo apt install steam-installer"
	else
		echo "!! No terminal for Steam's licence question; install it later: sudo apt install steam-installer"
	fi
fi

if [ ${#missing_debs[@]} -gt 0 ]; then
	dl=$(mktemp -d)
	debs=()
	for d in "${missing_debs[@]}"; do
		read -r pkg url sum <<<"$d"
		f="$dl/${url##*/}"
		curl -fsSL -o "$f" "$url"
		echo "$sum  $f" | sha256sum -c --quiet || { echo "Checksum mismatch for $pkg; stopping."; exit 1; }
		debs+=("$f")
	done
	wait_apt; sudo apt-get "${APT_WAIT[@]}" install -y "${debs[@]}"
	rm -rf "$dl"
fi

if ! $have_flathub; then
	sudo flatpak remote-add --if-not-exists flathub "$FLATHUB"
	# remote-add does not fetch the AppStream catalogue STORE reads
	sudo flatpak update -y --noninteractive --appstream flathub
fi
if [ ${#missing_flatpak[@]} -gt 0 ]; then
	sudo flatpak install -y --noninteractive flathub "${missing_flatpak[@]}"
fi
# Flatpak apps reach an NVIDIA GPU only through NVIDIA's libraries built for the exact
# running driver; without them Chromium draws everything on the CPU. Flatpak fetches
# them by itself only when the driver was already running at install time.
# (session/ultimit-flatpak-gpu repeats this per user at login, e.g. after a driver upgrade.)
if nv=$(cat /sys/module/nvidia/version 2>/dev/null) && [ -n "$nv" ]; then
	nv_gl=org.freedesktop.Platform.GL.nvidia-$(printf %s "$nv" | tr . -)
	flatpak list --runtime --columns=application | grep -qx "$nv_gl" ||
		sudo flatpak install -y --noninteractive flathub "$nv_gl" ||
		echo "No Flatpak GL libraries on Flathub for NVIDIA $nv yet; Flatpak apps run without the GPU."
fi

# System config files (distro/system mirrors /), e.g. the virtual camera and the
# FIREWALL helper (executables keep their x bit; everything is root-owned).
for f in $(cd "$ROOT/distro/system" && find . -name __pycache__ -prune -o -type f -print); do
	mode=644; [ -x "$ROOT/distro/system/$f" ] && mode=755
	cmp -s "$ROOT/distro/system/$f" "/$f" || sudo install -D -m $mode "$ROOT/distro/system/$f" "/$f"
done

if ! $have_dxvk; then
	sudo "$ROOT/scripts/get-dxvk.sh" /opt/ultimit/dxvk
fi
echo "Done."
