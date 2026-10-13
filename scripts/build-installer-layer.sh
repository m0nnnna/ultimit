#!/bin/bash
# The extra packages the Ultimit installer screen needs in the ISO's live system, as one archive
# that greeter/installer/start.sh unpacks over it: distro/packages-installer.txt plus the libraries
# the release's binaries link to (its distro/packages-runtime.txt), minus what the live system
# already has, with their dependencies. Downloaded from Ubuntu's archive; no root needed.
#
#   scripts/build-installer-layer.sh UBUNTU_SERVER_ISO RELEASE OUT.tar.zst
# Needs xorriso (XORRISO=... to use another), unsquashfs, zstd, apt-get, dpkg-deb.
set -euo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
ISO=$1 RELEASE=$2 OUT=$3
XORRISO=${XORRISO:-xorriso}
export LC_ALL=C
w=$(mktemp -d /var/tmp/ultimit-layer.XXXXXX)
trap 'rm -rf "$w"' EXIT

# ---- what the live system has: the installer layer's dpkg status
layer=$($XORRISO -indev "$ISO" -find /casper -name '*.installer.squashfs' 2>/dev/null | tr -d "'" | head -n1)
[ -n "$layer" ] || { echo "no installer layer in $ISO" >&2; exit 1; }
$XORRISO -osirrox on -indev "$ISO" -extract "$layer" "$w/live.squashfs" >/dev/null 2>&1
unsquashfs -q -no-xattrs -d "$w/live" "$w/live.squashfs" var/lib/dpkg/status >/dev/null
status=$w/live/var/lib/dpkg/status
awk '$1=="Package:"{p=$2} $1=="Status:" && $4=="installed"{print p}' "$status" | sort -u >"$w/have"

# ---- what the screen needs, minus that
list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep -v '^$' || true; }
{ list "$ROOT/distro/packages-installer.txt"; tar -xzOf "$RELEASE" opt/ultimit/distro/packages-runtime.txt; } \
	| sort -u | comm -23 - "$w/have" >"$w/want"

# ---- resolve and download with a private apt (Ubuntu 26.04's archive, the live system's status)
mkdir -p "$w/apt/state/lists/partial" "$w/apt/cache/archives/partial" "$w/apt/etc"
cat >"$w/apt/etc/ubuntu.sources" <<'EOF'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: resolute resolute-updates resolute-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
A=(-o Dir::Etc::SourceList=/dev/null -o "Dir::Etc::SourceParts=$w/apt/etc" -o Dir::Etc::Preferences=/dev/null
	-o Dir::Etc::PreferencesParts=/dev/null -o "Dir::State=$w/apt/state" -o "Dir::State::status=$status"
	-o "Dir::Cache=$w/apt/cache" -o Debug::NoLocking=1 -o APT::Architecture=amd64 -o APT::Architectures=amd64
	-o APT::Install-Recommends=false -q)
apt-get "${A[@]}" update >/dev/null
mapfile -t want <"$w/want"
apt-get "${A[@]}" -y -d install "${want[@]}" >/dev/null
n=$(ls "$w"/apt/cache/archives/*.deb | wc -l)

# ---- unpack into one tree, pack it
mkdir -p "$w/stage"
for d in "$w"/apt/cache/archives/*.deb; do dpkg-deb -x "$d" "$w/stage"; done
rm -rf "$w/stage/usr/share/doc" "$w/stage/usr/share/man" "$w/stage/usr/share/lintian" "$w/stage/usr/share/locale"
tar -C "$w/stage" --owner=0 --group=0 --zstd -cf "$OUT" .
echo "$OUT: $n packages, $(du -h "$OUT" | cut -f1)"
