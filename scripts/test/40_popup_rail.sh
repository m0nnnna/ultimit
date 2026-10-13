# Popups and the shell rail's window list.

scenario_popup_on_screen() {
	python3 -c "import PIL" 2>/dev/null || note "PIL missing: popup bounds not checked"
	open_app gtk Probe $PROBE || return; local id=$WID
	# Bottom-right of the window: the menu cannot fit below/right of the pointer.
	local x y
	x=$(sj "W($id)['content']['x']+W($id)['content']['width']-30"); y=$(sj "W($id)['content']['y']+W($id)['content']['height']-20")
	ptr_to 600 300; sleep 0.5
	grim "$RUNDIR/before.png"
	click "$x" "$y" right
	sleep 1.2
	snap
	grim "$RUNDIR/after.png"
	local res
	if res=$(python3 "$STATE_PY" popup "$RUNDIR/before.png" "$RUNDIR/after.png" 2>&1) && [ "$res" != none ]; then
		read -r px0 py0 px1 py1 <<<"$res"
		note "popup ~ $px0,$py0..$px1,$py1 (click at $x,$y)"
		assert_json "$px0>=0 and $py0>=0 and $px1<=full['width'] and $py1<=full['height']" "popup inside the output ($px0,$py0..$px1,$py1)"
		assert_json "$px0>=usable['x'] and $py1<=usable['y']+usable['height']" "popup inside the usable area (not over rail/ticker)"
		assert_json "$px1-$px0>100 and $py1-$py0>60" "popup has a sensible size"
	else
		python3 -c "import PIL" 2>/dev/null && fail "no popup visible after right-click ($res)"
	fi
	keys -k Escape
}

# The rail's WINDOWS list: one entry per toplevel, oldest first. The shell reports where each
# entry is (windows[].rail in ultimitctl state), so the click doesn't depend on how many apps
# are pinned above the list.
scenario_rail_window_list() {
	open_app gtk Probe $PROBE || return; local a=$WID
	open_app gtk Probe $PROBE || return; local b=$WID
	sleep 1 # rail entry add-transition
	grim -g "0,0 84x720" "$OUTDIR/rail_window_list__rail.png"
	assert_json "W($b)['focused']" "newest window focused before the click"
	assert_soon "W($a)['rail'] is not None" "the shell reported the oldest window's rail entry"
	local rx ry
	read -r rx ry < <(sj "(lambda r: '%d %d' % (r['x'] + r['width'] // 2, r['y'] + r['height'] // 2))(W($a)['rail'])")
	click "$rx" "$ry"
	assert_soon "W($a)['focused'] and not W($b)['focused']" "clicking the first WINDOWS entry focuses the oldest window"
	ptr_to 600 300
	snap
}
