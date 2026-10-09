#!/bin/sh
# Build the pieces Ubuntu 26.04 doesn't ship (or ships unusably) into
# ~/.local/ultimit-deps:
#   wlroots 0.19.2  Ubuntu's copy is linked with -Bsymbolic-functions, which
#                   stops SceneFX's scene overrides from taking effect.
#   SceneFX 0.4.1   blur, shadows, clipped regions on the wlroots scene graph.
#   Quickshell      the QML toolkit the Ultimit shell is written in.
# Builds use -j4; the dev laptop runs out of RAM with more.
set -e
P=${ULTIMIT_DEPS:-$HOME/.local/ultimit-deps}
SRC=${ULTIMIT_SRC:-$HOME/.local/src}
export PKG_CONFIG_PATH="$P/lib/x86_64-linux-gnu/pkgconfig"
mkdir -p "$SRC"

fetch() { # url tag dir
	[ -d "$SRC/$3" ] || git -c advice.detachedHead=false clone -q --depth 1 -b "$2" "$1" "$SRC/$3"
}

fetch https://gitlab.freedesktop.org/wlroots/wlroots.git 0.19.2 wlroots
meson setup --reconfigure "$SRC/wlroots/build" "$SRC/wlroots" --prefix="$P" --buildtype=release \
	-Dexamples=false -Dwerror=false -Dxwayland=enabled \
	-Dbackends=drm,libinput,x11 -Drenderers=gles2,vulkan
ninja -C "$SRC/wlroots/build" -j4 install

fetch https://github.com/wlrfx/scenefx 0.4.1 scenefx
meson setup --reconfigure "$SRC/scenefx/build" "$SRC/scenefx" --prefix="$P" --buildtype=release \
	-Dexamples=false -Dc_link_args="-Wl,-rpath,$P/lib/x86_64-linux-gnu"
ninja -C "$SRC/scenefx/build" -j4 install

fetch https://github.com/quickshell-mirror/quickshell v0.3.2 quickshell
cmake -GNinja -S "$SRC/quickshell" -B "$SRC/quickshell/build" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
	-DCMAKE_INSTALL_PREFIX="$P" -DCRASH_HANDLER=OFF -DDISTRIBUTOR="Ultimit dev build"
cmake --build "$SRC/quickshell/build" -j 4
cmake --install "$SRC/quickshell/build"
