#!/bin/bash
# Build the Ultimit ISO: Ubuntu 26.04's server ISO, patched so that its installer sets up Ultimit.
# It starts the Ultimit installer screen (greeter/installer: Wi-Fi, which drive, keep Windows in
# the free space or erase, name and password), then Ubuntu's installer (subiquity) installs Ubuntu
# without any desktop, the NVIDIA driver when the PC needs it, and Ultimit precompiled (no
# building). Apps (Flatpaks, Wine, DXVK) install on the first boot. If the screen can't start,
# Ubuntu's own text questions take over.
#
#   scripts/build-iso.sh UBUNTU_SERVER_ISO RELEASE [OUT.iso]
#     UBUNTU_SERVER_ISO   ubuntu-26.04.x-live-server-amd64.iso from releases.ubuntu.com
#     RELEASE             ultimit-<version>-amd64.tar.gz from scripts/build-release.sh
#   --text                       no Ultimit screen: Ubuntu's text questions
#   --unattended USER PASSWORD   test builds: no questions at all, this user, the whole first disk
#
# Needs xorriso (sudo apt install xorriso). The installer needs internet: Ultimit's packages come
# from Ubuntu's archive.
set -euo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
UNATTENDED=false SCREEN=true USER_NAME="" PASSWORD=""
args=()
while [ $# -gt 0 ]; do
	case "$1" in
	--unattended) UNATTENDED=true SCREEN=false USER_NAME=$2 PASSWORD=$3; shift 2 ;;
	--text) SCREEN=false ;;
	-h | --help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) args+=("$1") ;;
	esac
	shift
done
[ ${#args[@]} -ge 2 ] || { sed -n '9,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
SRC_ISO=${args[0]} RELEASE=${args[1]}
ver=$(basename "$RELEASE" | sed -n 's/^ultimit-\(.*\)-amd64\.tar\.gz$/\1/p')
[ -n "$ver" ] || { echo "RELEASE should be ultimit-<version>-amd64.tar.gz" >&2; exit 2; }
OUT=${args[2]:-ultimit-$ver-amd64.iso}
XORRISO=${XORRISO:-xorriso}
command -v "${XORRISO%% *}" >/dev/null || { echo "xorriso is needed: sudo apt install xorriso" >&2; exit 1; }
tar -tzf "$RELEASE" opt/ultimit/scripts/system-install.sh >/dev/null || { echo "$RELEASE isn't an Ultimit release" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# ---- boot menu: "Install Ultimit" first, with autoinstall on --------------------------------
# subiquity-storage-version=2: subiquity's newer partitioning (as Ubuntu's desktop installer uses);
# with the old one, autoinstall's "use the free space" finds no gap on a drive that has partitions.
cat >"$work/grub.cfg" <<'GRUB'
set timeout=10

loadfont unicode

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "Install Ultimit" {
    set gfxpayload=keep
    linux  /casper/vmlinuz  autoinstall  subiquity-storage-version=2  ---
    initrd /casper/initrd
}
menuentry "Try or Install Ubuntu Server (no Ultimit)" {
    set gfxpayload=keep
    linux  /casper/vmlinuz  ---
    initrd /casper/initrd
}
grub_platform
if [ "$grub_platform" = "efi" ]; then
menuentry 'Boot from next volume' {
    exit 1
}
menuentry 'UEFI Firmware Settings' {
    fwsetup
}
fi
GRUB

# ---- the installer's answers ---------------------------------------------------------------
# base.json: what is always the same (the Ultimit screen adds the drive and who you are, see
# greeter/installer/answers.py); autoinstall.yaml on the ISO: that plus how to ask the rest.
hash=""
if $UNATTENDED; then hash=$(openssl passwd -6 "$PASSWORD"); how=unattended
elif $SCREEN; then how=screen
else how=text; fi
python3 - "$work" "$ver" "$how" "$USER_NAME" "$hash" <<'PY'
import json, sys
work, ver, how, user, pwhash = sys.argv[1:6]
base = {
    "version": 1,
    "source": {"id": "ubuntu-server-minimal"},
    "drivers": {"install": True},        # third-party drivers (NVIDIA), like the desktop installer
    "codecs": {"install": True},
    "updates": "security",
    "shutdown": "reboot",
    "late-commands": [
        # Ultimit, precompiled, onto the new system; then its setup inside it (packages from the
        # archive, the Ultimit login screen, fonts, helpers). Apps follow on the first boot.
        "tar -C /target -xzf /cdrom/ultimit/ultimit-%s-amd64.tar.gz" % ver,
        "curtin in-target --target=/target -- /opt/ultimit/scripts/system-install.sh --apps-at-first-boot --desktop-network",
        "curtin in-target --target=/target -- sh -c 'cp /var/log/installer/autoinstall-user-data /var/log/ultimit-autoinstall.yaml 2>/dev/null || true'",
    ],
}
json.dump(base, open(work + "/base.json", "w"), indent=2)
iso = dict(base)
iso["storage"] = {"layout": {"name": "direct"}}
if how == "unattended":
    iso["identity"] = {"hostname": "ultimit", "realname": user, "username": user, "password": pwhash}
else:
    # Ubuntu's text questions: what the Ultimit screen answers (or all of it, if it can't start)
    iso["interactive-sections"] = ["keyboard", "network", "storage", "identity"]
    if how == "screen":
        iso["early-commands"] = ["sh /cdrom/ultimit/installer/start.sh"]
with open(work + "/autoinstall.yaml", "w") as f:
    f.write("# Ultimit %s: Ubuntu 26.04 without a desktop, then Ultimit (scripts/build-iso.sh)\n" % ver)
    json.dump({"autoinstall": iso}, f, indent=2)   # JSON is YAML
PY
if $SCREEN; then
	echo "Building the installer screen's packages..."
	XORRISO="$XORRISO" "$ROOT/scripts/build-installer-layer.sh" "$SRC_ISO" "$RELEASE" "$work/installer-layer.tar.zst"
	tar -xzOf "$RELEASE" opt/ultimit/greeter/installer/start.sh >"$work/start.sh" 2>/dev/null \
		|| cp "$ROOT/greeter/installer/start.sh" "$work/start.sh"
fi

# ---- md5sum.txt: keep "Check disc for defects" honest for the files we change -----------------
$XORRISO -osirrox on -indev "$SRC_ISO" -extract /md5sum.txt "$work/md5sum.txt" >/dev/null 2>&1
chmod u+w "$work/md5sum.txt"
sed -i '\#\./boot/grub/grub\.cfg$#d; \#\./autoinstall\.yaml$#d; \#\./ultimit/#d' "$work/md5sum.txt"
sum() { printf '%s  ./%s\n' "$(md5sum "$1" | cut -d' ' -f1)" "$2" >>"$work/md5sum.txt"; }
sum "$work/grub.cfg" boot/grub/grub.cfg
sum "$work/autoinstall.yaml" autoinstall.yaml
sum "$RELEASE" "ultimit/$(basename "$RELEASE")"
extra=()
if $SCREEN; then
	sum "$work/installer-layer.tar.zst" ultimit/installer-layer.tar.zst
	sum "$work/start.sh" ultimit/installer/start.sh
	sum "$work/base.json" ultimit/installer/base.json
	extra=(-map "$work/installer-layer.tar.zst" /ultimit/installer-layer.tar.zst
		-map "$work/start.sh" /ultimit/installer/start.sh
		-map "$work/base.json" /ultimit/installer/base.json)
fi

# ---- repack: same boot setup as Ubuntu's ISO, our files added ----------------------------------
rm -f "$OUT"
$XORRISO -indev "$SRC_ISO" -outdev "$OUT" \
	-map "$work/grub.cfg" /boot/grub/grub.cfg \
	-map "$work/autoinstall.yaml" /autoinstall.yaml \
	-map "$RELEASE" "/ultimit/$(basename "$RELEASE")" \
	-map "$work/md5sum.txt" /md5sum.txt "${extra[@]}" \
	-boot_image any replay 2>&1 | grep -vE "^xorriso : (UPDATE|NOTE)" | tail -3
sha256sum "$OUT" >"$OUT.sha256"
echo "$OUT ($(du -h "$OUT" | cut -f1))$($UNATTENDED && echo "  UNATTENDED TEST BUILD: wipes the first disk without asking")"
