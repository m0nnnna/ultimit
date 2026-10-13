#!/bin/bash
# Build the Ultimit ISO: Ubuntu 26.04's server ISO, patched so that its installer sets up Ultimit.
# The installer asks for the disk and for your name, user name and password (plus keyboard and
# network), then installs Ubuntu without any desktop, the NVIDIA driver when the PC needs it, and
# Ultimit precompiled (no building). Apps (Steam, Wine, Flatpaks, DXVK) install on the first boot.
#
#   scripts/build-iso.sh UBUNTU_SERVER_ISO RELEASE [OUT.iso]
#     UBUNTU_SERVER_ISO   ubuntu-26.04.x-live-server-amd64.iso from releases.ubuntu.com
#     RELEASE             ultimit-<version>-amd64.tar.gz from scripts/build-release.sh
#   --unattended USER PASSWORD   test builds: no questions at all, this user, the whole first disk
#
# Needs xorriso (sudo apt install xorriso). The installer needs internet: Ultimit's packages come
# from Ubuntu's archive.
set -euo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
UNATTENDED=false USER_NAME="" PASSWORD=""
args=()
while [ $# -gt 0 ]; do
	case "$1" in
	--unattended) UNATTENDED=true USER_NAME=$2 PASSWORD=$3; shift 2 ;;
	-h | --help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) args+=("$1") ;;
	esac
	shift
done
[ ${#args[@]} -ge 2 ] || { sed -n '8,11p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
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
cat >"$work/grub.cfg" <<'GRUB'
set timeout=10

loadfont unicode

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "Install Ultimit" {
    set gfxpayload=keep
    linux  /casper/vmlinuz  autoinstall  ---
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

# ---- the installer's answers -------------------------------------------------------------------
if $UNATTENDED; then
	hash=$(python3 -c 'import crypt,sys; print(crypt.crypt(sys.argv[1], crypt.mksalt(crypt.METHOD_SHA512)))' "$PASSWORD" 2>/dev/null \
		|| openssl passwd -6 "$PASSWORD")
	questions="  identity:
    hostname: ultimit
    realname: \"$USER_NAME\"
    username: $USER_NAME
    password: \"$hash\"
  storage:
    layout:
      name: direct"
else
	# What it asks: keyboard, network, disk, and who you are. Everything else is decided here.
	questions="  interactive-sections:
    - keyboard
    - network
    - storage
    - identity
  storage:
    layout:
      name: direct"
fi
cat >"$work/autoinstall.yaml" <<YAML
# Ultimit $ver: Ubuntu 26.04 without a desktop, then Ultimit (scripts/build-iso.sh)
autoinstall:
  version: 1
$questions
  source:
    id: ubuntu-server-minimal
  # Third-party drivers (NVIDIA) and media codecs, like the desktop installer offers
  drivers:
    install: true
  codecs:
    install: true
  updates: security
  shutdown: reboot
  late-commands:
    # Ultimit, precompiled, onto the new system; then its setup inside it (packages from the
    # archive, the Ultimit login screen, fonts, helpers). Apps follow on the first boot.
    - tar -C /target -xzf /cdrom/ultimit/ultimit-$ver-amd64.tar.gz
    - curtin in-target --target=/target -- /opt/ultimit/scripts/system-install.sh --apps-at-first-boot --desktop-network
    - curtin in-target --target=/target -- sh -c 'cp /var/log/installer/autoinstall-user-data /var/log/ultimit-autoinstall.yaml 2>/dev/null || true'
YAML

# ---- md5sum.txt: keep "Check disc for defects" honest for the files we change -----------------
$XORRISO -osirrox on -indev "$SRC_ISO" -extract /md5sum.txt "$work/md5sum.txt" >/dev/null 2>&1
chmod u+w "$work/md5sum.txt"
sed -i '\#\./boot/grub/grub\.cfg$#d; \#\./autoinstall\.yaml$#d; \#\./ultimit/#d' "$work/md5sum.txt"
( cd "$work" && printf '%s  ./boot/grub/grub.cfg\n' "$(md5sum grub.cfg | cut -d' ' -f1)" \
	&& printf '%s  ./autoinstall.yaml\n' "$(md5sum autoinstall.yaml | cut -d' ' -f1)" ) >>"$work/md5sum.txt"
printf '%s  ./ultimit/%s\n' "$(md5sum "$RELEASE" | cut -d' ' -f1)" "$(basename "$RELEASE")" >>"$work/md5sum.txt"

# ---- repack: same boot setup as Ubuntu's ISO, our files added ----------------------------------
rm -f "$OUT"
$XORRISO -indev "$SRC_ISO" -outdev "$OUT" \
	-map "$work/grub.cfg" /boot/grub/grub.cfg \
	-map "$work/autoinstall.yaml" /autoinstall.yaml \
	-map "$RELEASE" "/ultimit/$(basename "$RELEASE")" \
	-map "$work/md5sum.txt" /md5sum.txt \
	-boot_image any replay 2>&1 | grep -vE "^xorriso : (UPDATE|NOTE)" | tail -3
sha256sum "$OUT" >"$OUT.sha256"
echo "$OUT ($(du -h "$OUT" | cut -f1))$($UNATTENDED && echo "  UNATTENDED TEST BUILD: wipes the first disk without asking")"
