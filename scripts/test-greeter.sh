#!/bin/sh
# Show the Ultimit greeter in a window on the current desktop, in demo mode
# (no real logins: password "demo" succeeds and just logs the session).
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEPS=${ULTIMIT_DEPS:-/opt/ultimit}   # scripts/install.sh builds wlroots, SceneFX and Quickshell there
ULTIMIT_GREETER_DEMO=1 exec "$ROOT/compositor/build/ultimit" -x -s "$DEPS/bin/qs -p '$ROOT/greeter'"
