#!/bin/sh
# Build and run Ultimit in a window on the current desktop.
#   scripts/run-nested.sh                 compositor + Ultimit shell
#   scripts/run-nested.sh -s "ptyxis"     with a different startup command
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEPS=${ULTIMIT_DEPS:-/opt/ultimit}   # scripts/install.sh builds wlroots, SceneFX and Quickshell there
export PKG_CONFIG_PATH="$DEPS/lib/x86_64-linux-gnu/pkgconfig"
export LD_LIBRARY_PATH="$DEPS/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$DEPS/bin:$PATH"

BUILD="$ROOT/compositor/build"
[ -d "$BUILD" ] || meson setup "$BUILD" "$ROOT/compositor" --prefix="$DEPS"
# -j4: the dev laptop has little RAM to spare.
ninja -C "$BUILD" -j4

if [ $# -eq 0 ]; then
	set -- -s "qs -p '$ROOT/shell'"
fi
exec "$BUILD/ultimit" "$@"
