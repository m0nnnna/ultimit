# Rail: pinned buttons own their windows (shell/RailWindows.qml). Driven through `qs ipc call railwin ...`
# (a click on the button runs the same code). Needs foot (CONSOLE button).
rl() { qs -p "$ROOT/shell" ipc call railwin "$@" 2>/dev/null; }
# rail_is PIN STATE MSG: the button reaches STATE ("count=1 open=true focused=true minimized=false") within a few seconds
rail_is() {
	local i st
	for i in $(seq 1 25); do st=$(rl state "$1"); [ "$st" = "$2" ] && return 0; sleep 0.3; done
	fail "$3 [got: $st]"; return 1
}

scenario_rail_pinned_windows() {
	have qs || skip "qs missing"
	have foot || skip "foot missing"
	assert_eq "$(rl state term)" "count=0 open=false focused=false minimized=false" "CONSOLE starts closed"
	mark_ids
	assert_eq "$(rl click term)" ok "click CONSOLE with no window"
	WID=$(wait_for_window foot 25) || { fail "CONSOLE click did not launch foot"; return; }
	local a=$WID
	rail_is term "count=1 open=true focused=true minimized=false" "button shows one focused window"
	assert_eq "$(rl unowned)" "" "the foot window is not in WINDOWS"
	snap open
	rl click term >/dev/null
	assert_soon "W($a)['minimized']" "click on the focused window minimizes it"
	rail_is term "count=1 open=true focused=false minimized=true" "button shows minimized"
	assert_eq "$(rl unowned)" "" "minimized window still not in WINDOWS"
	assert_json "W($a)['rail'] and W($a)['rail']['x']<84 and W($a)['rail']['height']==64" "minimize target is the CONSOLE button, not a WINDOWS entry"
	snap minimized
	rl click term >/dev/null
	assert_soon "not W($a)['minimized'] and W($a)['focused']" "click again restores and focuses"
	# a second window: count 2, click cycles, middle-click/new opens another
	mark_ids
	rl newwindow term >/dev/null
	local b; b=$(wait_for_window foot 25) || { fail "New window did not open a second foot"; return; }
	rail_is term "count=2 open=true focused=true minimized=false" "two windows counted"
	assert_soon "W($b)['focused']" "the new window has focus"
	rl click term >/dev/null
	assert_soon "W($a)['focused']" "click cycles to the other window"
	rl click term >/dev/null
	assert_soon "W($b)['focused']" "and back"
	snap two
	close_win "$b"; close_win "$a"
	rail_is term "count=0 open=false focused=false minimized=false" "closing every window clears the indicator"
}

# GAMES owns only Ultimit's own library window: a (minimized) Steam must not light it up, and
# Steam's window stays under WINDOWS. foot stands in for Steam via --app-id.
scenario_rail_games_not_open() {
	have qs || skip "qs missing"
	have foot || skip "foot missing"
	open_app wl steam foot --app-id=steam || return; local s=$WID
	ctl minimize "$s" >/dev/null
	assert_soon "W($s)['minimized']" "steam minimized"
	rail_is games "count=0 open=false focused=false minimized=false" "GAMES is not open because Steam is"
	assert_eq "$(rl unowned)" "steam" "Steam is listed under WINDOWS"
}
