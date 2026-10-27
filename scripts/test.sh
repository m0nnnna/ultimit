#!/bin/bash
# Ultimit end-to-end tests: boots a headless devbox (the freshly built
# compositor/build/ultimit + the shell), drives it with wlrctl/wtype, checks
# it through shell/bin/ultimitctl and grim, and prints a PASS/FAIL table.
#
#   scripts/test.sh                 run every scenario
#   scripts/test.sh NAME...         run only the named scenarios (e.g. placement)
#   scripts/test.sh --list          list scenarios
#
# Results: test-results/<timestamp>/<scenario>.png (screenshot) and .json
# (ultimitctl state), plus devbox.log and apps.log. Exit status is non-zero
# if any scenario FAILs (XFAIL = known bug, SKIP = missing app: both OK).
#
# Needs: wlrctl wtype grim python3, dbus-run-session; foot for the window tests.
# Runs nothing in your live session: it refuses to start if a devbox is
# already running, only ever talks to the devbox socket, and only signals
# processes it spawned itself.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export ROOT
DEVBOX_STATE="${XDG_RUNTIME_DIR:-/tmp}/ultimit-devbox"
LIVE_DISPLAY=${WAYLAND_DISPLAY:-}
LIVE_XDISPLAY=${DISPLAY:-}

for f in "$ROOT"/scripts/test/[0-9]*.sh; do SCENARIO_FILES+=("$f"); done
list_scenarios() { grep -h -o '^scenario_[a-z0-9_]*' "${SCENARIO_FILES[@]}" | sed 's/^scenario_//'; }

if [ "${1:-}" = "--list" ]; then list_scenarios; exit 0; fi

for tool in wlrctl wtype grim python3 dbus-run-session setsid; do
	command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 2; }
done
[ -x "$ROOT/compositor/build/ultimit" ] || { echo "compositor/build/ultimit not built" >&2; exit 2; }
if [ -f "$DEVBOX_STATE/pid" ] && kill -0 "$(cat "$DEVBOX_STATE/pid")" 2>/dev/null; then
	echo "a devbox is already running (pid $(cat "$DEVBOX_STATE/pid")); stop it first: scripts/devbox.sh stop" >&2
	exit 2
fi

TS=$(date +%Y%m%d-%H%M%S)
OUTDIR="$ROOT/test-results/$TS"
RUNDIR=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/ultimit-test.XXXXXX")
APPDATA="$RUNDIR/xdg-data"
mkdir -p "$OUTDIR" "$RUNDIR/cur" "$APPDATA"
: >"$RUNDIR/pids"
export OUTDIR RUNDIR APPDATA DEVBOX_STATE

# shellcheck source=test/lib.sh
. "$ROOT/scripts/test/lib.sh"
for f in "${SCENARIO_FILES[@]}"; do . "$f"; done

STARTED=0
cleanup() {
	trap - EXIT INT TERM
	[ -n "${SOCK:-}" ] && reset_world 2>/dev/null
	cp "$DEVBOX_STATE/log" "$OUTDIR/devbox.log" 2>/dev/null
	[ "$STARTED" = 1 ] && "$ROOT/scripts/devbox.sh" stop >/dev/null 2>&1
	rm -rf "$RUNDIR"
}
trap cleanup EXIT
trap 'echo; echo "interrupted"; exit 130' INT TERM

# Game Mode (scripts/test/70_gamemode.sh): a fake power-profiles-daemon, never the real one.
export ULTIMIT_FAKE_PPD="$RUNDIR/ppd" ULTIMIT_STATE_DIR="$RUNDIR/state"
echo balanced >"$ULTIMIT_FAKE_PPD"
echo "== starting devbox"
"$ROOT/scripts/devbox.sh" start || exit 2
STARTED=1
SOCK=$(sock_name)
if [ -z "$SOCK" ] || [ "$SOCK" = "$LIVE_DISPLAY" ] || [ "$SOCK" = wayland-0 ]; then
	echo "refusing to run: devbox socket '$SOCK' looks like the live session" >&2
	exit 2
fi
export SOCK WAYLAND_DISPLAY="$SOCK"
export ULTIMIT_SOCK="${XDG_RUNTIME_DIR:-/tmp}/ultimit-$SOCK.sock"
unset DISPLAY
XDISP=$(xdisplay)
if [ -n "$XDISP" ] && [ "$XDISP" = "$LIVE_XDISPLAY" ]; then XDISP=; fi # never touch the live X display
export XDISP
PATH="$ROOT/shell/bin:$PATH"
echo "devbox: WAYLAND_DISPLAY=$SOCK results: ${OUTDIR#"$ROOT"/}"
echo "== waiting for the shell"
wait_shell 60 || echo "!! shell layers did not all appear within 60s"
sleep 1

declare -a ROWS
NFAIL=0
only=("$@")

run_one() {
	local name=$1 start=$SECONDS status detail
	SCENARIO=$name
	rm -f "$RUNDIR"/cur/*
	# XWayland is lazy; its DISPLAY shows up in the log at start.
	XDISP=$(xdisplay); [ "$XDISP" = "$LIVE_XDISPLAY" ] && XDISP=; export XDISP
	echo "-- $name"
	if ! kill -0 "$(cat "$DEVBOX_STATE/pid" 2>/dev/null)" 2>/dev/null; then
		echo "compositor is not running anymore" >"$(cur fail)"
	else
		( "scenario_$name" )
		[ -e "$(cur snapped)" ] || snap
	fi
	if [ -s "$(cur fail)" ]; then
		status=FAIL; detail=$(head -n1 "$(cur fail)"); NFAIL=$((NFAIL + 1))
	elif [ -s "$(cur xfail)" ]; then
		status=XFAIL; detail=$(sort -u "$(cur xfail_reason)" | paste -sd"~" | sed "s/~/; /g")
	elif [ -s "$(cur skip)" ]; then
		status=SKIP; detail=$(cat "$(cur skip)")
	else
		status=PASS; detail=$(paste -sd';' "$(cur notes)" 2>/dev/null)
	fi
	# A skip inside a scenario that otherwise passed shows its notes too.
	[ "$status" = XFAIL ] && [ -s "$(cur notes)" ] && detail="$detail; $(paste -sd';' "$(cur notes)")"
	ROWS+=("$(printf '%-18s %-6s %3ss  %s' "$name" "$status" $((SECONDS - start)) "$detail")")
	reset_world
}

for name in $(list_scenarios); do
	if [ ${#only[@]} -gt 0 ]; then
		match=0; for o in "${only[@]}"; do [ "$o" = "$name" ] && match=1; done
		[ $match = 1 ] || continue
	fi
	run_one "$name"
done

echo
echo "scenario           result  time  detail"
echo "------------------------------------------------------------------------------"
for r in "${ROWS[@]}"; do echo "$r"; done | tee "$OUTDIR/summary.txt"
echo "------------------------------------------------------------------------------"
echo "screenshots + state: test-results/$TS/ (summary.txt)"
if [ "$NFAIL" -gt 0 ]; then echo "FAILED ($NFAIL)"; exit 1; fi
echo "OK"
