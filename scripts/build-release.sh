#!/bin/bash
# Pack a finished Ultimit (/opt/ultimit, as scripts/install.sh leaves it) into a precompiled release
# that installs without building: the Ultimit ISO (scripts/build-iso.sh) carries one, and
#   sudo /opt/ultimit/scripts/system-install.sh --release ultimit-<version>-amd64.tar.gz
# installs it on any Ubuntu 26.04. Build it on a clean machine (a fresh VM), not a development one.
#
#   scripts/build-release.sh [OUT_DIR]      (default: the current folder)
set -euo pipefail
PREFIX=/opt/ultimit
OUT=${1:-.}
[ -x "$PREFIX/bin/ultimit" ] && [ -x "$PREFIX/bin/qs" ] && [ -d "$PREFIX/shell" ] \
	|| { echo "No complete $PREFIX here: run scripts/install.sh first." >&2; exit 1; }
[ -f /usr/lib/x86_64-linux-gnu/security/pam_oo7.so ] || { echo "pam_oo7.so missing" >&2; exit 1; }
ver=$(cat "$PREFIX/VERSION")
case "$ver" in *-dirty) echo "warning: $PREFIX was installed from a checkout with uncommitted changes ($ver)" >&2 ;; esac
out="$OUT/ultimit-$ver-amd64.tar.gz"
# Headers, pkg-config files and the build markers only matter for building on top of it.
tar -C / -z --owner=0 --group=0 \
	--exclude="opt/ultimit/include" --exclude="opt/ultimit/lib/x86_64-linux-gnu/pkgconfig" \
	--exclude="opt/ultimit/.built-*" --exclude="opt/ultimit/dxvk" --exclude="__pycache__" \
	-cf "$out" opt/ultimit usr/lib/x86_64-linux-gnu/security/pam_oo7.so
sha256sum "$out" >"$out.sha256"
echo "$out ($(du -h "$out" | cut -f1))"
