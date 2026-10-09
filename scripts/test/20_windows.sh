# Window geometry, placement, focus and window-state changes.

# check_frame ID LABEL WANT_SSD
check_frame() {
	local id=$1 label=$2 want=$3 bar; bar=$(BAR_EXPR "$id")
	assert_eq "$(wf "$id" "w['ssd']")" "$want" "$label ssd"
	assert_json "(lambda w, c, f: f['x']==c['x']-1 and f['y']==c['y']-$bar-1 and f['width']==c['width']+2 and f['height']==c['height']+$bar+2)(W($id), W($id)['content'], W($id)['frame'])" \
		"$label frame == content + 1px border (+34 titlebar if ssd)"
	assert_json "W($id)['tree']['x']==W($id)['content']['x'] and W($id)['tree']['y']==W($id)['content']['y']" "$label scene tree origin == content origin"
	assert_json "(W($id)['geometry_offset']['width'], W($id)['geometry_offset']['height'])==(W($id)['content']['width'], W($id)['content']['height'])" \
		"$label content size == client window geometry"
	assert_json "W($id)['content']['width']>0 and W($id)['content']['height']>0" "$label non-empty content"
}

scenario_frame_alignment() {
	local n=0 name
	# name | kind | app_id match | want_ssd | command...
	while IFS='|' read -r name kind app ssd cmd; do
		[ -z "$name" ] && continue
		local exe=${cmd%% *}
		if ! have "$exe" || { [ "$kind" = x ] && [ -z "$XDISP" ]; }; then note "skipped $name (not installed)"; continue; fi
		# shellcheck disable=SC2086
		open_app "$kind" "$app" $cmd || continue
		n=$((n + 1))
		check_frame "$WID" "$name" "$ssd"
		close_win "$WID" || fail "$name did not close"
	done <<'APPS'
text-editor(gtk4)|gtk|TextEditor|False|gnome-text-editor
calculator(gtk4)|gtk|Calculator|False|gnome-calculator
zenity(gtk3)|gtk|zenity|False|zenity --info --text=frame-test
foot(wayland)|wl|foot|True|foot
xterm(x11)|x|xterm|True|xterm
xeyes(x11)|x|xeyes|True|xeyes
xmessage(x11)|x|Xmessage|True|xmessage -geometry 400x150 frame-test
APPS
	[ "$n" -gt 0 ] || skip "no test apps installed"
}

scenario_placement() {
	have gnome-text-editor || skip "gnome-text-editor not installed"
	local ids=() i
	for i in 1 2 3; do
		open_app gtk TextEditor gnome-text-editor || return
		ids+=("$WID")
	done
	local a=${ids[0]} b=${ids[1]} c=${ids[2]}
	assert_json "len({(w['content']['x'], w['content']['y']) for w in wins})==3" "3 windows have distinct content top-left (staggered)"
	assert_json "all(abs(p['content']['x']-q['content']['x'])>=24 or abs(p['content']['y']-q['content']['y'])>=24 for p in wins for q in wins if p['id']<q['id'])" \
		"no two windows start within 24px of each other"
	assert_json "all(w['frame']['x']>=usable['x'] and w['frame']['y']>=usable['y'] and w['frame']['x']+w['frame']['width']<=usable['x']+usable['width'] and w['frame']['y']+w['frame']['height']<=usable['y']+usable['height'] for w in wins)" \
		"all frames fully inside the usable area"
	note "ids $a $b $c: $(sj "[box(w['content'])[:2] for w in wins]")"
	snap
}

scenario_focus_and_raise() {
	have gnome-text-editor || skip "gnome-text-editor not installed"
	open_app gtk TextEditor gnome-text-editor || return; local a=$WID
	open_app gtk TextEditor gnome-text-editor || return; local b=$WID
	assert_json "W($b)['focused'] and not W($a)['focused']" "newest window starts focused"
	assert_json "wins[0]['id']==$b" "newest window is on top"
	# A is offset up-left of B, so a strip of A's left edge is uncovered.
	local x y
	x=$(sj "W($a)['content']['x']+14"); y=$(sj "W($a)['content']['y']+300")
	assert_json "W($a)['content']['x']+14 < W($b)['frame']['x']" "test point on A is not covered by B"
	click "$x" "$y"
	assert_soon "W($a)['focused'] and not W($b)['focused']" "clicking the background window focuses it"
	assert_soon "wins[0]['id']==$a" "clicked window is raised to the top"
	snap
	# and focus can go back
	x=$(sj "W($b)['content']['x']+W($b)['content']['width']-12"); y=$(sj "W($b)['content']['y']+300")
	click "$x" "$y"
	assert_soon "W($b)['focused']" "clicking B focuses it again"
}

# check_states ID LABEL: maximize / fullscreen / minimize via ultimitctl and keys
check_states() {
	local id=$1 label=$2 geo0 bar; bar=$(BAR_EXPR "$id")
	"$ROOT/shell/bin/ultimitctl" focus "$id" >/dev/null
	wait_json "W($id)['focused']" 3
	geo0=$(sj "box(W($id)['content'])")
	local max="box(W($id)['content'])==(usable['x']+1, usable['y']+$bar+1, usable['width']-2, usable['height']-$bar-2)"
	local fs="box(W($id)['content'])==(full['x'], full['y'], full['width'], full['height'])"
	local back="box(W($id)['content'])==$geo0"

	ctl maximize "$id" >/dev/null
	assert_soon "W($id)['maximized'] and $max" "$label maximize (ctl): content fills usable area minus titlebar"
	ctl maximize "$id" >/dev/null
	assert_soon "not W($id)['maximized'] and $back" "$label un-maximize (ctl) restores geometry $geo0"

	ctl fullscreen "$id" >/dev/null
	assert_soon "W($id)['fullscreen'] and $fs" "$label fullscreen (ctl): content == full output"
	ctl fullscreen "$id" >/dev/null
	assert_soon "not W($id)['fullscreen'] and $back" "$label leave fullscreen (ctl) restores geometry"

	ctl minimize "$id" >/dev/null
	assert_soon "W($id)['minimized'] and not W($id)['focused']" "$label minimize (ctl)"
	ctl minimize "$id" >/dev/null
	assert_soon "not W($id)['minimized']" "$label restore from minimize (ctl)"
	assert_json "$back" "$label geometry unchanged by minimize/restore"

	# Keybindings act on the focused window.
	ctl focus "$id" >/dev/null; wait_json "W($id)['focused']" 3
	keys -M alt -k F10 -m alt
	assert_soon "W($id)['maximized'] and $max" "$label Alt+F10 maximizes"
	keys -M alt -k F10 -m alt
	assert_soon "not W($id)['maximized'] and $back" "$label Alt+F10 again restores"
	keys -M alt -k F11 -m alt
	assert_soon "W($id)['fullscreen'] and $fs" "$label Alt+F11 fullscreens"
	keys -M alt -k F11 -m alt
	assert_soon "not W($id)['fullscreen'] and $back" "$label Alt+F11 again restores"
	keys -M logo -k Down -m logo
	assert_soon "W($id)['minimized']" "$label Super+Down minimizes"
	ctl focus "$id" >/dev/null
	assert_soon "not W($id)['minimized'] and W($id)['focused'] and $back" "$label focus restores a minimized window to its old geometry"
}

scenario_maximize_fullscreen_minimize() {
	local ran=0
	if have gnome-text-editor; then
		open_app gtk TextEditor gnome-text-editor && { check_states "$WID" "text-editor(csd)"; ran=1; snap; close_win "$WID"; }
	fi
	if open_ssd_app; then
		check_states "$WID" "$SSD_APP(ssd)"; ran=1
	else
		note "ssd part skipped: neither foot nor xterm installed"
	fi
	[ $ran = 1 ] || skip "no apps available"
}
