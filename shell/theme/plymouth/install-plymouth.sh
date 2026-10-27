#!/bin/bash
# Installs (or with --uninstall removes) the Ultimit Plymouth boot splash. Runs as root;
# scripts/system-install.sh calls it. Safe to repeat (also how a skin/accent change is applied).
#
#   install-plymouth.sh [--skin NAME] [--accent #rrggbb] [--config shell.json] [--nvidia-early-kms]
#   install-plymouth.sh --uninstall
#
# Changes: apt plymouth + python3-pil; /usr/share/plymouth/themes/ultimit; default Plymouth theme;
# /etc/default/grub.d/ultimit-splash.cfg (quiet splash); /etc/systemd/system/plymouth-quit.service.d/
# (only if the stock unit lacks --retain-splash, for a seamless hand-off to greetd); NVIDIA KMS
# modprobe line only if nvidia-drm modeset is not already on; update-grub; update-initramfs -u.
set -euo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
THEME=/usr/share/plymouth/themes/ultimit
STATE=/var/lib/ultimit/plymouth-prev-theme
GRUBD=/etc/default/grub.d/ultimit-splash.cfg
QUITD=/etc/systemd/system/plymouth-quit.service.d/ultimit-retain-splash.conf
NVCONF=/etc/modprobe.d/ultimit-nvidia-drm.conf
INITMOD=/etc/initramfs-tools/modules
UNINSTALL=false EARLY=false ARGS=()
while [ $# -gt 0 ]; do
	case "$1" in
	--uninstall) UNINSTALL=true ;;
	--nvidia-early-kms) EARLY=true ;;
	--skin | --accent | --config) ARGS+=("$1" "$2"); shift ;;
	-h | --help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done
[ "$(id -u)" = 0 ] || { echo "install-plymouth.sh runs as root" >&2; exit 1; }
say() { printf '   %s\n' "$*"; }
export DEBIAN_FRONTEND=noninteractive

refresh_boot() {
	if command -v update-grub >/dev/null; then update-grub >/dev/null 2>&1 && say "update-grub done" || say "! update-grub failed"; fi
	update-initramfs -u >/dev/null && say "update-initramfs -u done"
}

if $UNINSTALL; then
	echo "Removing the Ultimit boot splash"
	if command -v plymouth-set-default-theme >/dev/null && [ -f "$STATE" ]; then
		prev=$(cat "$STATE")
		plymouth-set-default-theme "${prev:-bgrt}" 2>/dev/null && say "default theme back to ${prev:-bgrt}" || true
	fi
	rm -rf "$THEME" "$STATE" "$GRUBD" "$NVCONF"
	rm -f "$QUITD"; rmdir "$(dirname "$QUITD")" 2>/dev/null || true
	[ -f "$INITMOD" ] && sed -i '/# ultimit-early-kms$/d' "$INITMOD"
	systemctl daemon-reload 2>/dev/null || true
	say "removed theme, grub drop-in, systemd and modprobe drop-ins (plymouth stays installed)"
	refresh_boot
	exit 0
fi

echo "Installing the Ultimit boot splash"
dpkg-query -W -f='${Status}' plymouth 2>/dev/null | grep -q "install ok installed" \
	&& dpkg-query -W -f='${Status}' python3-pil 2>/dev/null | grep -q "install ok installed" \
	|| { apt-get install -y -q plymouth python3-pil; say "installed plymouth, python3-pil"; }

# default config: the user who ran sudo
if ! printf '%s\n' "${ARGS[@]:-}" | grep -qx -- --config && [ -n "${SUDO_USER:-}" ]; then
	h=$(getent passwd "$SUDO_USER" | cut -d: -f6)
	[ -f "$h/.config/ultimit/shell.json" ] && ARGS+=(--config "$h/.config/ultimit/shell.json")
fi
stage=$(mktemp -d); trap 'rm -rf "$stage"' EXIT
python3 "$HERE/build-plymouth.py" "$stage/ultimit" --install-dir "$THEME" "${ARGS[@]}"
rm -rf "$THEME.new"; mkdir -p "$(dirname "$THEME")"
cp -a "$stage/ultimit" "$THEME.new"; chmod -R go-w,a+rX "$THEME.new"
rm -rf "$THEME"; mv "$THEME.new" "$THEME"
say "theme written to $THEME"
find /usr/lib -name script.so -path '*plymouth*' 2>/dev/null | grep -q . || say "! plymouth's script module not found (script.so); the splash will not show"

# remember the previous default theme once, then make ours the default
mkdir -p /var/lib/ultimit
if [ ! -f "$STATE" ]; then
	prev=$(plymouth-set-default-theme 2>/dev/null || true)
	[ "$prev" = ultimit ] && prev=""
	printf '%s\n' "$prev" >"$STATE"
fi
plymouth-set-default-theme ultimit && say "default Plymouth theme: ultimit"

# kernel command line, via a drop-in (never edits /etc/default/grub). Ubuntu's grub scripts add
# vt.handoff=7 themselves once "splash" is present.
mkdir -p /etc/default/grub.d
cat >"$GRUBD" <<'CFG'
# Written by Ultimit (shell/theme/plymouth/install-plymouth.sh): the boot splash
for w in quiet splash; do
	case " $GRUB_CMDLINE_LINUX_DEFAULT " in *" $w "*) ;; *) GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT $w" ;; esac
done
GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT# }"
CFG
say "wrote $GRUBD"

# greetd is ordered After=plymouth-quit-wait.service, which ends when plymouth-quit.service has
# stopped plymouthd; that costs nothing extra. Plain "plymouth quit" clears the screen, though, so
# the stock unit must use --retain-splash: the last splash frame stays up until the greeter draws.
if ! systemctl cat plymouth-quit.service 2>/dev/null | grep -q -- '--retain-splash'; then
	mkdir -p "$(dirname "$QUITD")"
	printf '# Written by Ultimit: keep the splash on screen until the login screen draws\n[Service]\nExecStart=\nExecStart=-/usr/bin/plymouth quit --retain-splash\n' >"$QUITD"
	systemctl daemon-reload
	say "plymouth-quit.service now uses --retain-splash"
else
	say "plymouth-quit.service already retains the splash"
fi

# NVIDIA: nvidia-drm needs modeset=1 for Plymouth/Wayland; drivers >= 560 default to it
if lsmod 2>/dev/null | grep -q '^nvidia_drm' || lspci -n 2>/dev/null | grep -qE ' 03(00|02): 10de:'; then
	if grep -rqsE 'nvidia[-_]drm.*modeset=1' /etc/modprobe.d /usr/lib/modprobe.d /lib/modprobe.d /proc/cmdline \
		|| [ "$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null)" = Y ] \
		|| { v=$(modinfo -F version nvidia 2>/dev/null | cut -d. -f1); [ "${v:-0}" -ge 560 ]; }; then
		say "nvidia-drm modeset already on"
	else
		printf '# Written by Ultimit\noptions nvidia-drm modeset=1 fbdev=1\n' >"$NVCONF"
		say "added $NVCONF (nvidia-drm modeset=1)"
	fi
	if $EARLY && ! grep -q '# ultimit-early-kms$' "$INITMOD" 2>/dev/null; then
		for m in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do echo "$m # ultimit-early-kms" >>"$INITMOD"; done
		say "NVIDIA modules added to the initramfs (splash at native resolution from the start)"
	fi
fi

refresh_boot
echo "Done. Takes effect on the next boot; undo with: $0 --uninstall"
