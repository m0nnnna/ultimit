#!/bin/bash
# Build NekoPlayer, Ultimit's music player (the rail's AUDIO), into PREFIX/nekoplayer.
# scripts/install.sh runs it (as your user; sudo for the copy), so a release carries the
# finished app and system-install.sh only links it into the system (nekoplayer command, menu
# entry for audio files, icon).
#
#   scripts/build-nekoplayer.sh WORK_DIR [PREFIX]      (PREFIX default: /opt/ultimit)
#
# NekoPlayer is Flutter: the pinned, checksum-verified Flutter SDK is kept in WORK_DIR (like
# Rust for oo7; your own Flutter setup is not touched). The NekoPlayer commit is pinned below.
# The library and settings stay per user (~/.local/share/io.github.m0nnnna.nekoplayer).
set -euo pipefail
NEKOPLAYER_URL=https://github.com/m0nnnna/nekoplayer
NEKOPLAYER_REF=421788e7efa6f2489cb97c917acf051b9523b730   # branch ultimit
FLUTTER_VERSION=3.47.7
FLUTTER_SHA256=af7455f540df951184c7953fbe3cf884766e7541dacf8571f9f582db03dd6230
WORK=${1:?usage: build-nekoplayer.sh WORK_DIR [PREFIX]}
PREFIX=${2:-/opt/ultimit}
N=$PREFIX/nekoplayer

if [ "$(cat "$N/REF" 2>/dev/null)" = "$NEKOPLAYER_REF" ] && [ -x "$N/nekoplayer" ]; then
	echo "   already installed"; exit 0
fi

# Flutter SDK
F=$WORK/flutter-$FLUTTER_VERSION
if [ ! -x "$F/flutter/bin/flutter" ]; then
	echo "   getting Flutter $FLUTTER_VERSION (kept in $WORK)"
	tarball=$WORK/flutter_linux_$FLUTTER_VERSION-stable.tar.xz
	if ! echo "$FLUTTER_SHA256  $tarball" | sha256sum -c --status 2>/dev/null; then
		curl -fsSL -o "$tarball" "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_$FLUTTER_VERSION-stable.tar.xz"
		echo "$FLUTTER_SHA256  $tarball" | sha256sum -c --status || { echo "Flutter download doesn't match its checksum" >&2; exit 1; }
	fi
	rm -rf "$F" && mkdir -p "$F"
	tar -C "$F" -xJf "$tarball"
fi
export PATH="$F/flutter/bin:$PATH" PUB_CACHE="$WORK/pub-cache" FLUTTER_SUPPRESS_ANALYTICS=true
flutter --disable-analytics >/dev/null 2>&1 || true
flutter config --no-cli-animations --enable-linux-desktop >/dev/null 2>&1 || true

d=$WORK/src/nekoplayer
if [ ! -d "$d/.git" ]; then rm -rf "$d"; git clone -q --filter=blob:none "$NEKOPLAYER_URL" "$d"; fi
git -C "$d" fetch -q origin "$NEKOPLAYER_REF"
git -C "$d" -c advice.detachedHead=false checkout -q --force FETCH_HEAD
git -C "$d" clean -qfdx -e build -e .dart_tool

echo "   flutter build linux"
( cd "$d" && flutter pub get --suppress-analytics >/dev/null && flutter build linux --release --suppress-analytics ) >/dev/null
B=$d/build/linux/x64/release/bundle
[ -x "$B/nekoplayer" ] || { echo "the build has no $B/nekoplayer" >&2; exit 1; }

# Staged next to the old one and swapped in at the end, so a failed build leaves it working
sudo rm -rf "$N.new"; sudo mkdir -p "$N.new/share"
sudo cp -a "$B/." "$N.new/"
sudo install -m644 "$d/ultimit/nekoplayer.svg" "$N.new/share/nekoplayer.svg"
sudo tee "$N.new/share/nekoplayer.desktop" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=NekoPlayer
GenericName=Music Player
Comment=Play your music
Exec=$N/nekoplayer %F
Icon=nekoplayer
Terminal=false
Categories=AudioVideo;Audio;Player;
MimeType=audio/mpeg;audio/mp3;audio/flac;audio/x-flac;audio/ogg;audio/x-vorbis+ogg;audio/opus;audio/x-opus+ogg;audio/wav;audio/x-wav;audio/vnd.wave;audio/aac;audio/mp4;audio/x-m4a;
StartupWMClass=nekoplayer
StartupNotify=false
EOF
echo "$NEKOPLAYER_REF" | sudo tee "$N.new/REF" >/dev/null
sudo rm -rf "$N.old"; [ -e "$N" ] && sudo mv "$N" "$N.old"
sudo mv "$N.new" "$N"; sudo rm -rf "$N.old"
echo "   NekoPlayer ${NEKOPLAYER_REF:0:7} in $N"
