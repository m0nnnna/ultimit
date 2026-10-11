#!/bin/sh
# Install DXVK (Direct3D 8/9/10/11 -> Vulkan for Wine games) from the
# official release, pinned and checksum-verified. Ubuntu 26.04 only ships
# the 64-bit build; 32-bit Direct3D 9 games such as WoW 3.3.5a need x32.
#
#   scripts/get-dxvk.sh            -> ~/.local/share/ultimit/dxvk/<ver>, current -> <ver>
#   sudo scripts/get-dxvk.sh /opt/ultimit/dxvk   (ISO / system-wide)
set -eu
VER=3.1.1
SHA256=40565b4a724aadc4433fa4e010b4b23916d9b1f1baeee64e17186db94f54e608
URL="https://github.com/doitsujin/dxvk/releases/download/v$VER/dxvk-$VER.tar.gz"
DEST=${1:-${XDG_DATA_HOME:-$HOME/.local/share}/ultimit/dxvk}

if [ -e "$DEST/$VER/x32/d3d9.dll" ]; then
	ln -sfn "$VER" "$DEST/current"
	echo "DXVK $VER already in $DEST"; exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL --proto '=https' -o "$work/dxvk.tar.gz" "$URL"
echo "$SHA256  $work/dxvk.tar.gz" | sha256sum -c --quiet -
mkdir "$work/x"
tar -xzf "$work/dxvk.tar.gz" -C "$work/x" --no-same-owner --no-same-permissions
src="$work/x/dxvk-$VER"
[ -f "$src/x32/d3d9.dll" ] && [ -f "$src/x64/d3d9.dll" ] || { echo "unexpected archive layout"; exit 1; }
mkdir -p "$DEST/$VER"
cp -r "$src/x32" "$src/x64" "$DEST/$VER/"
chmod -R a+rX "$DEST/$VER"
ln -sfn "$VER" "$DEST/current"
echo "DXVK $VER installed in $DEST"
