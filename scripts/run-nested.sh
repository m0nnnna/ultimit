#!/bin/sh
# Build and run Ultimit in a window on the current desktop.
#   scripts/run-nested.sh                 just the compositor
#   scripts/run-nested.sh -s "ptyxis"     with a startup command
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEPS=${ULTIMIT_DEPS:-$HOME/.local/ultimit-deps}
export PKG_CONFIG_PATH="$DEPS/lib/x86_64-linux-gnu/pkgconfig"
export LD_LIBRARY_PATH="$DEPS/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$DEPS/bin:$PATH"

BUILD="$ROOT/compositor/build"
[ -d "$BUILD" ] || meson setup "$BUILD" "$ROOT/compositor" --prefix="$DEPS"
# -j4: the dev laptop has little RAM to spare.
ninja -C "$BUILD" -j4

exec "$BUILD/ultimit" "$@"
