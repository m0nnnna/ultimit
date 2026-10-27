# Top bar (shell/components/TopBar.qml): one bar on the main display only, the time opens the clock +
# quick settings panel, notifications crawl in its ticker, and a fullscreen window hides it until the
# pointer is pushed to the top edge (compositor "edge" event, no polling).
# The devbox shell shares the live session bus, so notify-send would hit the real notification server:
# the ticker is fed through `qs ipc call notifs inject` instead (same path as the D-Bus intake after it).

qi() { qs -p "$ROOT/shell" ipc call "$@" 2>/dev/null; }
bar_mapped() { echo "(lambda l: bool(l) and l['mapped'])(layer('ultimit-topbar'))"; }

scenario_topbar_primary_only() {
	have qs || skip "qs missing"
	local pri; pri=$(sj "[o['name'] for o in s['outputs'] if o['primary']][0]")
	assert_json "len([l for l in s['layers'] if l['namespace']=='ultimit-topbar'])==1" "one bar with one output"
	local r; r=$(ctl test-output add 800 600) || true
	local sec; sec=$(echo "$r" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))")
	[ -n "$sec" ] || { fail "could not add a second output: $r"; return; }
	assert_soon "len(s['outputs'])==2" "second output present"
	assert_soon "len([l for l in s['layers'] if l['namespace']=='ultimit-wallpaper'])==2" "the shell paints both outputs" 10
	assert_json "len([l for l in s['layers'] if l['namespace']=='ultimit-topbar'])==1" "the bar is only on one output"
	assert_json "[l for l in s['layers'] if l['namespace']=='ultimit-topbar'][0]['output']=='$pri'" "...the main one"
	assert_json "layer('ultimit-ticker') is None" "no bottom strip on either output"
	snap two_outputs
	# the main display changes: the bar follows
	ctl primary "$sec" >/dev/null
	qi bar refresh >/dev/null
	assert_soon "[l for l in s['layers'] if l['namespace']=='ultimit-topbar'][0]['output']=='$sec'" "the bar moves to the new main display" 10
	# unplugged: it comes back to the remaining output
	ctl test-output remove "$sec" >/dev/null
	assert_soon "len(s['outputs'])==1" "second output gone"
	assert_soon "len([l for l in s['layers'] if l['namespace']=='ultimit-topbar'])==1 and layer('ultimit-topbar')['output']=='$pri'" "the bar is back on the remaining output" 12
}

scenario_topbar_clock_panel() {
	have qs || skip "qs missing"
	assert_eq "$(qi quicksettings state)" closed "panel closed at first"
	# a real click on the time (the last item of the bar)
	local w; w=$(sj "full['width']")
	click $((w - 40)) 16
	assert_soon "layer('ultimit-quicksettings') is not None and layer('ultimit-quicksettings')['mapped']" "click on the time opens the panel" 6
	assert_eq "$(qi quicksettings state)" open "panel state is open"
	sleep 0.6
	snap panel
	click $((w - 40)) 16
	sleep 0.5
	assert_eq "$(qi quicksettings state)" closed "a second click on the time closes it"
	# the old entry points reach the same panel
	qi quicksettings open >/dev/null
	assert_soon "layer('ultimit-quicksettings') and layer('ultimit-quicksettings')['mapped']" "IPC open shows the same panel" 6
	qi quicksettings close >/dev/null
	assert_soon "not layer('ultimit-quicksettings') or not layer('ultimit-quicksettings')['mapped']" "IPC close hides it" 6
	assert_json "layer('ultimit-status') is None" "no desktop clock layer"
}

scenario_topbar_ticker_notification() {
	have qs || skip "qs missing"
	qi notifs clear >/dev/null
	qi notifs dnd false >/dev/null
	local r; r=$(qi notifs inject "Mailer" "Build finished" "All 48 checks passed")
	case $r in held|"") fail "inject refused: '$r'"; return;; esac
	local i seen=
	for i in $(seq 1 20); do case $(qi notifs ticker) in *"Build finished"*) seen=1; break;; esac; sleep 0.25; done
	[ -n "$seen" ] || fail "the notification did not reach the ticker model: $(qi notifs ticker)"
	assert_eq "$(qi notifs ticker | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['app'])")" Mailer "it is the front item"
	sleep 1
	snap notif
	# do not disturb keeps new ones out
	qi notifs dnd true >/dev/null
	assert_eq "$(qi notifs inject Mailer Quiet shh)" held "DND: nothing added"
	qi notifs dnd false >/dev/null
	qi notifs clear >/dev/null
	assert_eq "$(qi notifs ticker)" "[]" "cleared"
}

scenario_topbar_fullscreen_reveal() {
	have foot || skip "foot missing"
	have qs || skip "qs missing"
	assert_soon "$(bar_mapped)" "bar shown on the desktop" 6 || return
	assert_json "layer('ultimit-topbar')['layer']==2 and layer('ultimit-topbar')['exclusive_zone']==32" "bar sits on the top layer with its zone"
	open_ssd_app || { skip "no terminal"; }
	local a=$WID
	ptr_to 640 360
	ctl fullscreen "$a" >/dev/null
	assert_soon "W($a)['fullscreen']" "window is fullscreen" 6 || return
	assert_soon "not ($(bar_mapped))" "the bar is hidden over a fullscreen window" 6
	snap hidden
	# push the pointer into the top edge: the bar slides over the window on the overlay layer
	wlrctl pointer move 0 -500
	assert_soon "$(bar_mapped) and layer('ultimit-topbar')['layer']==3" "the top edge reveals the bar over the window" 6
	sleep 0.5
	snap revealed
	# the pointer leaves it: away again
	ptr_to 640 400
	assert_soon "not ($(bar_mapped))" "the bar slides away when the pointer leaves" 6
	# no fullscreen: the bar is back in its place
	ctl fullscreen "$a" >/dev/null
	assert_soon "not W($a)['fullscreen']" "window leaves fullscreen" 6
	assert_soon "$(bar_mapped) and layer('ultimit-topbar')['layer']==2" "the bar is back on the top layer" 6
	close_win "$a"
}
