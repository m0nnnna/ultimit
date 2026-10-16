# Server-side titlebar (compositor drawn).

# tb_buttons ID: locate the three titlebar buttons from the compositor's state
# (windows[].buttons: minimize, maximize, close as layout boxes). Sets BMIN BMAX
# BCLOSE (x centres), BY and BW (cell width).
tb_buttons() {
	local id=$1
	ptr_to 600 600; sleep 0.3
	read -r BMIN BMAX BCLOSE BY BW < <(sj "(lambda b: '%d %d %d %d %d' % (b[0]['x']+b[0]['width']//2, b[1]['x']+b[1]['width']//2, b[2]['x']+b[2]['width']//2, b[2]['y']+b[2]['height']//2, b[2]['width']))(W($id)['buttons'])")
}

scenario_titlebar_buttons() {
	open_ssd_app || skip "neither foot nor xterm installed"
	local id=$WID
	# Below the toasts (top right, ~920-1260 x 104-182 on the 1280x720 devbox): they cover a titlebar button there.
	ctl move "$id" 150 250 >/dev/null
	assert_soon "box(W($id)['content'])[:2]==(150, 250)" "window moved to 150,250"
	assert_json "W($id)['ssd']" "$SSD_APP has a server-side titlebar"
	local geo0; geo0=$(sj "box(W($id)['content'])")
	tb_buttons "$id"
	note "buttons at x=$BMIN/$BMAX/$BCLOSE y=$BY cell=${BW}px"
	snap

	# [ _ ] minimize
	click "$BMIN" "$BY"
	assert_soon "W($id)['minimized']" "[ _ ] button minimizes"
	ctl focus "$id" >/dev/null
	assert_soon "not W($id)['minimized']" "window restored after minimize"
	assert_json "box(W($id)['content'])==$geo0" "geometry unchanged after minimize/restore"

	# [ □ ] maximize, again to restore
	tb_buttons "$id"
	click "$BMAX" "$BY"
	assert_soon "W($id)['maximized']" "[ □ ] button maximizes"
	tb_buttons "$id"
	click "$BMAX" "$BY"
	assert_soon "not W($id)['maximized'] and box(W($id)['content'])==$geo0" "[ □ ] button again restores geometry"

	# double-click on the titlebar toggles maximize (title area, left of buttons)
	local tx ty
	tx=$(sj "W($id)['frame']['x']+60"); ty=$(sj "W($id)['frame']['y']+19")
	ptr_to "$tx" "$ty"; sleep 0.1
	wlrctl pointer click left; wlrctl pointer click left
	assert_soon "W($id)['maximized']" "double-click on titlebar maximizes"
	sleep 0.6 # outside the double-click window

	# A plain click (no drag) on a maximized titlebar must not change anything.
	# Regression: a plain click on a maximized titlebar must not restore it
	# (fixed by restoring only once a drag actually moves).
	tx=$(sj "W($id)['frame']['x']+60"); ty=$(sj "W($id)['frame']['y']+19")
	click "$tx" "$ty"; sleep 0.8
	assert_json "W($id)['maximized']" "single click on a maximized titlebar leaves it maximized"
	# back to a known state: maximized
	[ "$(sj "W($id)['maximized']")" = True ] || ctl maximize "$id" >/dev/null
	assert_soon "W($id)['maximized']" "maximized again"
	sleep 0.6
	tx=$(sj "W($id)['frame']['x']+60"); ty=$(sj "W($id)['frame']['y']+19")
	ptr_to "$tx" "$ty"; sleep 0.1
	wlrctl pointer click left; wlrctl pointer click left
	assert_soon "not W($id)['maximized']" "double-click on a maximized titlebar un-maximizes"
	assert_json "box(W($id)['content'])==$geo0" "double-click restore returns to the previous geometry"

	# [ × ] close
	tb_buttons "$id"
	click "$BCLOSE" "$BY"
	assert_soon "not W($id)" "[ × ] button closes the window"
}
