#!/bin/sh
# Build the pieces Ubuntu 26.04 doesn't ship (or ships unusably) into
# ~/.local/ultimit-deps:
#   wlroots 0.19.2  Ubuntu's copy is linked with -Bsymbolic-functions, which
#                   stops SceneFX's scene overrides from taking effect.
#   SceneFX 0.4.1   blur, shadows, clipped regions on the wlroots scene graph.
#   Quickshell      the QML toolkit the Ultimit shell is written in.
#   oo7             Secret Service daemon (replaces gnome-keyring).
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

# oo7: Secret Service daemon replacing gnome-keyring (needs Rust >= 1.95;
# Ubuntu 26.04 ships 1.93, so use rustup's stable toolchain if present).
fetch https://github.com/linux-credentials/oo7 0.7.0.beta oo7
(
	cd "$SRC/oo7"
	PATH="$HOME/.cargo/bin:$PATH" cargo build --release -j 4 -p oo7-daemon -p oo7-pam -p oo7-cli
)
install -m755 "$SRC/oo7/target/release/oo7-daemon" "$SRC/oo7/target/release/oo7-cli" "$P/bin/"
echo "PAM module for login unlock (install as root):"
echo "  sudo install -m644 $SRC/oo7/target/release/libpam_oo7.so /lib/x86_64-linux-gnu/security/pam_oo7.so"
