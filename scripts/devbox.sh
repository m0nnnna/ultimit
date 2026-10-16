#!/bin/sh
# A disposable Ultimit for testing changes without logging out.
#
#   scripts/devbox.sh start [window]   start compositor + shell (headless by
#                                      default; "window" opens it on screen)
#   scripts/devbox.sh run CMD...       run a command inside it (apps, wtype,
#                                      wlrctl, grim...)
#   scripts/devbox.sh shot [FILE]      screenshot it (default /tmp/ultimit-devbox.png)
#   scripts/devbox.sh log              tail its log
#   scripts/devbox.sh stop             stop it
#
# Uses the freshly built compositor/build/ultimit, so it's how compositor
# changes get checked before anyone logs out and back in.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEPS=${ULTIMIT_DEPS:-/opt/ultimit}   # scripts/install.sh builds wlroots, SceneFX and Quickshell there
STATE="${XDG_RUNTIME_DIR:-/tmp}/ultimit-devbox"
mkdir -p "$STATE"

socket() { cat "$STATE/socket" 2>/dev/null; }
running() { [ -f "$STATE/pid" ] && kill -0 "$(cat "$STATE/pid")" 2>/dev/null; }

case "$1" in
start)
	running && { echo "devbox already running on $(socket)"; exit 0; }
	if [ "$2" = window ]; then backend=""; else backend=headless; fi
	(
		export PATH="$DEPS/bin:$ROOT/shell/bin:$PATH"
		export ULTIMIT_DEVBOX=1   # (the shell skips things like the update check)
		. "$ROOT/shell/theme/session-env.sh"
		# Don't inherit the parent's display or the devbox would nest
		# into whatever ran this script when headless.
		[ -n "$backend" ] && unset WAYLAND_DISPLAY DISPLAY
		# An empty WLR_BACKENDS means "no backends": only set it for headless.
		if [ -n "$backend" ]; then export WLR_BACKENDS=$backend; fi
		exec "$ROOT/compositor/build/ultimit" \
			-s "qs -p '$ROOT/shell'"
	) >"$STATE/log" 2>&1 &
	echo $! >"$STATE/pid"
	for _ in $(seq 50); do
		sock=$(sed -n 's/.*running on WAYLAND_DISPLAY=\([^ ]*\).*/\1/p' "$STATE/log")
		[ -n "$sock" ] && break
		sleep 0.1
	done
	[ -n "$sock" ] || { echo "devbox failed to start; see $STATE/log"; exit 1; }
	echo "$sock" >"$STATE/socket"
	echo "devbox running on WAYLAND_DISPLAY=$sock (pid $(cat "$STATE/pid"))"
	;;
run)
	shift
	running || { echo "devbox not running"; exit 1; }
	WAYLAND_DISPLAY=$(socket) GDK_BACKEND=wayland QT_QPA_PLATFORM=wayland \
		sh -c "$*" &
	;;
shot)
	running || { echo "devbox not running"; exit 1; }
	out=${2:-/tmp/ultimit-devbox.png}
	WAYLAND_DISPLAY=$(socket) grim "$out" && echo "$out"
	;;
log)
	tail -n "${2:-40}" "$STATE/log"
	;;
stop)
	if running; then
		kill -TERM "$(cat "$STATE/pid")"
		sleep 1
		running && kill -KILL "$(cat "$STATE/pid")"
	fi
	rm -f "$STATE/pid" "$STATE/socket"
	echo stopped
	;;
*)
	sed -n '2,12p' "$0"
	exit 1
	;;
esac
