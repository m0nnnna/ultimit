# shellcheck shell=bash
# Helpers for scripts/test.sh. Sourced, never run directly.
#
# Scenario contract: a function named scenario_<name>. Inside it use the
# assert_* helpers (they record failures and keep going), `skip "why"` to
# bail out with a SKIP row, `note "text"` for extra info in the table, and
# XFAIL_REASON="..." in front of an assert for a known compositor/shell bug.

STATE_PY="$ROOT/scripts/test/state.py"
# GTK4/libadwaita test window owned by the repo (GNOME apps get purged).
PROBE="python3 $ROOT/scripts/test/apps/gtk4-probe.py"

# ---- bookkeeping -------------------------------------------------------------

cur() { echo "$RUNDIR/cur/$1"; }

fail() {
	if [ -n "${XFAIL_REASON:-}" ]; then
		echo "$*" >>"$(cur xfail)"
		echo "$XFAIL_REASON" >>"$(cur xfail_reason)"
	else
		echo "$*" >>"$(cur fail)"
	fi
	echo "    ! $*" >&2
}
note() { echo "$*" >>"$(cur notes)"; echo "    . $*" >&2; }
skip() { echo "$*" >"$(cur skip)"; echo "    - SKIP: $*" >&2; exit 0; }
pass_note() { :; }

assert_eq() { # ACTUAL EXPECTED MSG
	if [ "$1" != "$2" ]; then fail "$3: got '$1', expected '$2'"; return 1; fi
}
assert_ne() { # A B MSG
	if [ "$1" = "$2" ]; then fail "$3: both '$1'"; return 1; fi
}
assert_json() { # PYEXPR MSG   (see state.py for the names available)
	local out
	if ! out=$(python3 "$STATE_PY" assert "$1" 2>&1); then
		fail "$2 [$out]"; return 1
	fi
}
# known_bug "reason" ASSERT_FN args...: run an assertion that is expected to
# fail because of a real compositor/shell bug (shown as XFAIL). If it starts
# passing, the table says so (XPASS note) so the marker can be removed.
known_bug() {
	local reason=$1; shift
	XFAIL_REASON=$reason "$@" && note "XPASS: '$2' passes now; drop known_bug"
	return 0
}
# sj EXPR -> print value of a python expression on the current state
sj() { python3 "$STATE_PY" eval "$1"; }

# wait_json PYEXPR [TIMEOUT_S]: poll until the expression is truthy.
wait_json() {
	local t=${2:-8} end
	end=$(($(date +%s%N) / 1000000 + t * 1000))
	while [ $(($(date +%s%N) / 1000000)) -lt "$end" ]; do
		python3 "$STATE_PY" assert "$1" >/dev/null 2>&1 && return 0
		sleep 0.15
	done
	return 1
}
# assert_soon PYEXPR MSG [TIMEOUT_S]: like assert_json but waits for it to hold.
assert_soon() {
	if ! wait_json "$1" "${3:-8}"; then
		local out; out=$(python3 "$STATE_PY" assert "$1" 2>&1)
		fail "$2 [$out]"; return 1
	fi
}

# ---- devbox ----------------------------------------------------------------------

sock_name() { cat "$DEVBOX_STATE/socket" 2>/dev/null; }

xdisplay() {
	sed -n 's/.*XWayland ready on DISPLAY=\(:[0-9]*\).*/\1/p' "$DEVBOX_STATE/log" | tail -1
}

wait_shell() { # until the shell's layers are mapped and the boot splash has come and gone
	wait_json "layer('ultimit-rail') and layer('ultimit-ticker') and layer('ultimit-status') and layer('ultimit-wallpaper')" "${1:-60}" || return 1
	sleep 1.5 # the boot splash layer is created slightly after the rest
	wait_json "not layer('ultimit-boot')" 30
}

# ---- apps ------------------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

mark_ids() { MARK=$(sj "max([w['id'] for w in wins] + [0])"); }

# spawn_app KIND CMD...   KIND: gtk | wl | x
# Every app runs in its own process group (killed by reset_world) and, for
# GTK, on a private session bus + scratch XDG_DATA_HOME so it can neither
# attach to the user's real app instances nor touch their drafts/settings.
spawn_app() {
	local kind=$1; shift
	(
		cd / || exit 1
		export WAYLAND_DISPLAY="$SOCK"
		case $kind in
		# no-portals: each app gets a private bus, and activating a portal
		# there can stall startup past the timeout (tests check windows, not portals).
		gtk) export GDK_BACKEND=wayland XDG_DATA_HOME="$APPDATA" GSETTINGS_BACKEND=memory GDK_DEBUG=no-portals GTK_USE_PORTAL=0
		     exec setsid dbus-run-session -- "$@" ;;
		x)   export DISPLAY="$XDISP"; unset GDK_BACKEND
		     exec setsid "$@" ;;
		*)   exec setsid "$@" ;;
		esac
	) >>"$RUNDIR/apps.log" 2>&1 &
	echo $! >>"$RUNDIR/pids"
}

# wait_for_window APP [TIMEOUT_S]: wait for a new (id > MARK) window whose
# app_id contains APP to be mapped and finished animating; prints its id.
wait_for_window() {
	local app=$1 t=${2:-20} end id
	end=$(($(date +%s%N) / 1000000 + t * 1000))
	while [ $(($(date +%s%N) / 1000000)) -lt "$end" ]; do
		id=$(APPMATCH="$app" MARK="$MARK" python3 "$STATE_PY" eval "next((w['id'] for w in apps(E['APPMATCH']) if w['id'] > I('MARK') and w['mapped'] and not w['animating']), '')" 2>/dev/null)
		if [ -n "$id" ]; then sleep 0.4; echo "$id"; return 0; fi
		sleep 0.2
	done
	return 1
}

# open_app KIND APPMATCH CMD... : launch and set WID to the new window id.
open_app() {
	local kind=$1 app=$2; shift 2
	mark_ids
	spawn_app "$kind" "$@"
	if ! WID=$(wait_for_window "$app" 25); then
		fail "window '$app' ($*) did not appear"; WID=; return 1
	fi
}

# Window field shortcuts: wf ID EXPR-on-window, e.g. wf 3 "w['ssd']"
wf() { WID_=$1 python3 "$STATE_PY" eval "(lambda w: $2)(W(I('WID_')))"; }

# ---- input -----------------------------------------------------------------------

ptr_to() { # X Y  (absolute: pointer move is relative, so go to 0,0 first)
	wlrctl pointer move -6000 -6000
	[ "$1" = 0 ] && [ "$2" = 0 ] || wlrctl pointer move "$1" "$2"
}
click() { # X Y [button]
	ptr_to "$1" "$2"; sleep 0.1
	wlrctl pointer click "${3:-left}"
}
# Keys via wtype. It drops the first key event of a run, so lead with a
# harmless Shift_L. Pass wtype args after, e.g. keys -M alt -k F10 -m alt
keys() { wtype -k Shift_L "$@"; }

# ---- screenshots / state per scenario ---------------------------------------------

snap() { # [SUFFIX]  -> <scenario>[__SUFFIX].png/.json
	local base="$OUTDIR/$SCENARIO${1:+__$1}"
	grim "$base.png" 2>/dev/null || note "grim failed"
	python3 "$STATE_PY" save "$base.json" 2>/dev/null
	[ -z "${1:-}" ] && touch "$(cur snapped)"
}

# ---- cleanup between scenarios -----------------------------------------------------

reset_world() {
	local id
	# Polite first.
	for id in $(python3 "$STATE_PY" eval "' '.join(str(w['id']) for w in wins)" 2>/dev/null); do
		"$ROOT/shell/bin/ultimitctl" close "$id" >/dev/null 2>&1
	done
	wait_json "not wins" 3 || true
	# Then everything we spawned.
	if [ -f "$RUNDIR/pids" ]; then
		while read -r p; do kill -TERM -- "-$p" 2>/dev/null; done <"$RUNDIR/pids"
		sleep 0.3
		while read -r p; do kill -KILL -- "-$p" 2>/dev/null; done <"$RUNDIR/pids"
		: >"$RUNDIR/pids"
	fi
	wait_json "not wins" 6 || echo "    ! windows left over after reset" >&2
	ptr_to 0 0
}

# ---- more helpers -------------------------------------------------------------------

close_win() { # ID: ask nicely, wait for it to go
	"$ROOT/shell/bin/ultimitctl" close "$1" >/dev/null 2>&1
	wait_json "not W($1)" 6
}

# An app that gets server-side decorations: foot, else xterm. Sets WID and
# SSD_APP; returns 1 (no window) if neither is installed or it failed to map.
open_ssd_app() {
	if have foot; then SSD_APP=foot; open_app wl foot foot
	elif have xterm && [ -n "${XDISP:-}" ]; then SSD_APP=xterm; open_app x xterm xterm
	elif have xmessage && [ -n "${XDISP:-}" ]; then SSD_APP=xmessage; open_app x Xmessage xmessage -geometry 500x200 "ultimit test window"
	else return 1; fi
}

BAR_EXPR() { echo "(34 if W($1)['ssd'] else 0)"; }
ctl() { "$ROOT/shell/bin/ultimitctl" "$@"; }
