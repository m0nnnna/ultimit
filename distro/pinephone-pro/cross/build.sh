#!/bin/sh
# Cross-build the Ultimit compositor for the PinePhone Pro on the PC (the phone overheats compiling)
# and install it there. The sysroot is a copy of the phone's headers and libraries:
#   ssh PHONE 'cd / && tar -c usr/include usr/lib/aarch64-linux-gnu usr/lib/gcc usr/share/pkgconfig \
#     usr/lib/pkgconfig usr/share/wayland usr/share/wayland-protocols opt/ultimit/include opt/ultimit/lib' \
#     | tar -x -C $SYSROOT
# Usage: build.sh [--install]   (PHONE=mino@192.168.0.195, SYSROOT, BUILD can be overridden)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
SYSROOT=${SYSROOT:-/run/media/mino/paizuri/ppp-sysroot}
BUILD=${BUILD:-/run/media/mino/paizuri/ppp-build/compositor}
PHONE=${PHONE:-mino@192.168.0.195}
mkdir -p "$(dirname "$BUILD")"
sed "s|@SYSROOT@|$SYSROOT|g" "$HERE/aarch64.ini.in" > "$(dirname "$BUILD")/aarch64.ini"
[ -f "$BUILD/build.ninja" ] || meson setup "$BUILD" "$ROOT/compositor" --cross-file "$(dirname "$BUILD")/aarch64.ini" \
	--buildtype=release -Dc_link_args="-Wl,-rpath,/opt/ultimit/lib/aarch64-linux-gnu"
ninja -C "$BUILD"
if [ "$1" = --install ]; then
	scp -q "$BUILD/ultimit" "$PHONE:/tmp/ultimit.new"
	ssh "$PHONE" 'sudo install -m755 /tmp/ultimit.new /opt/ultimit/bin/ultimit && rm /tmp/ultimit.new'
	echo "installed; restart the session to use it"
fi
