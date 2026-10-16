#!/bin/bash
# Remove the parts of Ubuntu's server image a gaming desktop never uses: SAN/LVM disk tools,
# crash-dump capture (its crashkernel= reservation holds back up to several GB of RAM), cloud
# provisioning, crash reporting to Ubuntu, modems, snapd (Ultimit uses Flatpak) and firmware for
# datacenter network cards. system-install.sh runs it on every install and update.
#
#   scripts/trim-ubuntu.sh          dry run: print what would go and what is kept
#   scripts/trim-ubuntu.sh --yes    do it (root)
#
# Anything this PC uses stays: LVM, multipath or iSCSI disks, a modem, snaps someone installed,
# and cloud-init until its first boot is done (it may still have the user account to set up).
# As in purge-gnome.sh, everything else apt would take along (the dependencies of the meta
# packages ubuntu-server-minimal and linux-firmware) is marked manually installed first, and
# nothing is removed if apt's plan holds anything unexpected. Snapd is pinned so it doesn't
# come back as a dependency. Rollback: sudo apt install <package>; for snapd, delete
# /etc/apt/preferences.d/ultimit-no-snapd first.
set -euo pipefail
export LC_ALL=C

TRIM=(kdump-tools ubuntu-fan apport apport-core-dump-handler needrestart
	linux-firmware-mellanox-spectrum linux-firmware-netronome linux-firmware-marvell-prestera linux-firmware-qlogic)
note() { printf '   %s\n' "$*"; }

types=$(lsblk -nro TYPE 2>/dev/null || true)
if grep -qx lvm <<<"$types" || { command -v pvs >/dev/null && [ -n "$(pvs --noheadings 2>/dev/null)" ]; }; then
	note "keeping lvm2: this PC has LVM volumes"
else TRIM+=(lvm2); fi
if grep -qx mpath <<<"$types"; then note "keeping multipath-tools: multipath disks in use"; else TRIM+=(multipath-tools); fi
if ls /sys/class/iscsi_session/* >/dev/null 2>&1 || [ -n "$(ls -A /etc/iscsi/nodes 2>/dev/null)" ]; then
	note "keeping open-iscsi: iSCSI disks configured"
else TRIM+=(open-iscsi); fi
if ls -d /sys/class/net/ww* >/dev/null 2>&1 || mmcli -L 2>/dev/null | grep -q /Modem/; then
	note "keeping modemmanager: a mobile-broadband modem is here"
else TRIM+=(modemmanager); fi
if [ -e /etc/cloud/cloud-init.disabled ] || cloud-init status 2>/dev/null | grep -qE "status: (done|disabled)"; then
	TRIM+=(cloud-init)
else note "keeping cloud-init until its first boot is done"; fi
# Snaps Ubuntu preinstalls; any other snap means someone uses snapd
user_snaps=$(snap list 2>/dev/null | awk 'NR > 1 {print $1}' |
	grep -vE '^(snapd|bare|core[0-9]*|hwctl|firmware-updater|snap-store|desktop-security-center|prompting-client|cups|gtk-common-themes|gnome-[0-9-]*|mesa-[0-9]*|chromium|firefox|thunderbird)$' || true)
if [ -n "$user_snaps" ]; then note "keeping snapd: snaps in use ($(tr '\n' ' ' <<<"$user_snaps"))"; else TRIM+=(snapd); fi

# Allowed to go along with them: the meta packages and LVM's own helpers
ALSO='^(ubuntu-server-minimal|ubuntu-server|linux-firmware|dmeventd|liblvm2cmd[0-9.]*|thin-provisioning-tools|libdevmapper-event[0-9.]*|lxd-installer|snapd-.*|apport-.*|python3-apport|python3-problem-report)$'

installed=()
for p in "${TRIM[@]}"; do
	dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" && installed+=("$p")
done
[ ${#installed[@]} -gt 0 ] || { note "nothing to trim"; exit 0; }

w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
plan() { apt-get -s purge --autoremove "${installed[@]}" 2>/dev/null | awk '/^Purg/ {print $2}' | sed 's/:.*//' | sort -u; }
plan >"$w/all"
printf '%s\n' "${installed[@]}" | sort -u >"$w/trim"
comm -23 "$w/all" "$w/trim" >"$w/along"
grep -E "$ALSO" "$w/along" >"$w/allowed" || true
comm -23 "$w/along" "$w/allowed" >"$w/keep"
note "removing: $(tr '\n' ' ' <"$w/trim")"
[ -s "$w/allowed" ] && note "with: $(tr '\n' ' ' <"$w/allowed")"
[ -s "$w/keep" ] && note "keeping $(wc -l <"$w/keep") packages apt would autoremove with them"
if [ "${1:-}" != "--yes" ]; then
	echo "Dry run. Run with --yes (as root) to do it."
	exit 0
fi
[ "$(id -u)" = 0 ] || { echo "trim-ubuntu.sh --yes runs as root" >&2; exit 1; }

[ -s "$w/keep" ] && apt-mark manual $(cat "$w/keep") >/dev/null
plan >"$w/final"
sort -u "$w/trim" "$w/allowed" >"$w/expected"
if [ -n "$(comm -23 "$w/final" "$w/expected")" ]; then
	echo "Unexpected removals; nothing removed: $(comm -23 "$w/final" "$w/expected" | tr '\n' ' ')" >&2
	exit 1
fi
cmdline_crash=false; grep -q crashkernel= /proc/cmdline && cmdline_crash=true
DEBIAN_FRONTEND=noninteractive apt-get purge --autoremove -y -q "${installed[@]}" >/dev/null
if printf '%s\n' "${installed[@]}" | grep -qx snapd; then
	printf 'Package: snapd\nPin: release a=*\nPin-Priority: -10\n' >/etc/apt/preferences.d/ultimit-no-snapd
	rm -rf /var/cache/snapd /snap 2>/dev/null || true
fi
# Without kdump-tools' grub snippet the next boot reserves no crash-kernel memory
if $cmdline_crash && ! grep -rqs crashkernel= /etc/default/grub /etc/default/grub.d && command -v update-grub >/dev/null; then
	update-grub >/dev/null 2>&1 && note "crash-kernel memory is free from the next boot" || note "update-grub failed; run it by hand"
fi
note "trimmed $(wc -l <"$w/final") packages"
