#!/bin/sh
# make-home.sh <dir>: build a fake HOME for tests (fixture desktop entries, Flatpak exports, a dummy DXVK).
set -e
H=${1:?home dir}
F=$(cd "$(dirname "$0")" && pwd)
rm -rf "$H"
mkdir -p "$H/.local/share/applications" "$H/.local/share/flatpak/exports/share/applications" "$H/.config/ultimit" "$H/icons"
cp "$F"/applications/*.desktop "$H/.local/share/applications/"
cp "$F"/flatpak/exports/share/applications/*.desktop "$H/.local/share/flatpak/exports/share/applications/"
mkdir -p "$H/.local/share/ultimit/dxvk"
cp -r "$F/dxvk/current" "$H/.local/share/ultimit/dxvk/"
sed "s#/tmp/claude-1000/games-home#$H#" "$F/applications/supertux.desktop" > "$H/.local/share/applications/supertux.desktop"
cat > "$H/icons/tux.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><ellipse cx="32" cy="38" rx="18" ry="22" fill="#111"/><ellipse cx="32" cy="42" rx="11" ry="15" fill="#eee"/><circle cx="26" cy="22" r="3" fill="#fff"/><circle cx="38" cy="22" r="3" fill="#fff"/><path d="M26 29h12l-6 6z" fill="#f90"/></svg>
SVG
