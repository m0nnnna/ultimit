# Several monitors: plug a virtual one in (ultimitctl test-output, headless devbox only), put a
# maximized window on it, unplug it again: the window lands on the main display, maximized there.
# Also: a new monitor's place in the layout, and the main display reported in state.

scenario_monitors_hotplug() {
	local name
	name=$(ctl test-output add 1920 1080 | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))")
	[ -n "$name" ] || skip "no headless backend (test-output add failed)"
	export NEW_OUT=$name
	assert_soon "O(E['NEW_OUT']) is not None and O(E['NEW_OUT'])['enabled']" "plugged-in monitor $name is in the layout"
	assert_json "O(E['NEW_OUT'])['mode']['width'] == 1920 and O(E['NEW_OUT'])['full']['width'] == 1920" "$name runs 1920x1080"
	assert_json "sum(1 for o in s['outputs'] if o['primary']) == 1 and not O(E['NEW_OUT'])['primary']" \
		"exactly one main display, and it is not the new monitor"
	assert_json "not any(o is not O(E['NEW_OUT']) and o['enabled'] and (lambda a, b: a['x'] < b['x'] + b['width'] and b['x'] < a['x'] + a['width'] and a['y'] < b['y'] + b['height'] and b['y'] < a['y'] + a['height'])(o['full'], O(E['NEW_OUT'])['full']) for o in s['outputs'])" \
		"the new monitor doesn't overlap the others"
	# the shell puts its panels on the new screen too (rail = exclusive zone on the left)
	assert_soon "O(E['NEW_OUT'])['usable']['x'] > O(E['NEW_OUT'])['full']['x']" "rail on the new monitor"

	open_ssd_app || { ctl test-output remove "$name" >/dev/null; skip "neither foot nor xterm available"; }
	local id=$WID nx ny
	read -r nx ny < <(sj "(lambda f: '%d %d' % (f['x'] + 300, f['y'] + 200))(O(E['NEW_OUT'])['full'])")
	ctl move "$id" "$nx" "$ny" >/dev/null
	ctl maximize "$id" >/dev/null
	assert_soon "W($id)['maximized'] and (lambda c, u: c['x'] >= u['x'] and c['x'] + c['width'] <= u['x'] + u['width'])(W($id)['content'], O(E['NEW_OUT'])['usable'])" \
		"window maximized on $name"
	snap with_new_monitor

	ctl test-output remove "$name" >/dev/null
	assert_soon "O(E['NEW_OUT']) is None" "$name unplugged"
	assert_soon "(lambda m, w: w['maximized'] and m['usable']['x'] <= w['content']['x'] and w['content']['x'] + w['content']['width'] <= m['usable']['x'] + m['usable']['width'] and w['content']['width'] > m['usable']['width'] * 0.8)(next(o for o in s['outputs'] if o['primary']), W($id))" \
		"its window moved to the main display, still maximized and fitted to it"
	snap after_unplug
	close_win "$id" || true
}
