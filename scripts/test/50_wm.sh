# Windows-style window management: snapping, Super shortcuts, Alt+Tab switcher.
# Needs foot (or xterm for the XWayland case). Drag-to-edge uses the
# `ultimitctl drag` test hook because wlrctl cannot hold a button.

# frame box of a snapped window: "side" is left|right, step 0|1|2 = 1/2, 1/3, 2/3
snap_frame_expr() { # SIDE STEP -> python tuple expr in usable coords
	local side=$1 step=$2 w
	case $step in
	1) w="usable['width']//3" ;;
	2) w="usable['width']-usable['width']//3" ;;
	*) if [ "$side" = left ]; then w="usable['width']//2"; else w="usable['width']-usable['width']//2"; fi ;;
	esac
	if [ "$side" = left ]; then echo "(usable['x'], usable['y'], $w, usable['height'])"
	else echo "(usable['x']+usable['width']-($w), usable['y'], $w, usable['height'])"; fi
}

check_snap() { # ID LABEL SIDE STEP
	local id=$1 label=$2 side=$3 step=$4
	assert_soon "W($id)['snapped']=='$side' and W($id)['snap_step']==$step and box(W($id)['frame'])==$(snap_frame_expr "$side" "$step")" \
		"$label frame == $side step $step of the usable area (titlebar/border fit exactly)"
	assert_json "not W($id)['maximized'] and not W($id)['fullscreen']" "$label snapped is not maximized"
}

wm_snap_checks() { # ID LABEL
	local id=$1 label=$2 geo0
	ctl focus "$id" >/dev/null; wait_json "W($id)['focused']" 3
	geo0=$(sj "box(W($id)['content'])")
	assert_json "W($id)['snapped'] is None" "$label starts unsnapped"

	keys -M logo -k Left -m logo
	check_snap "$id" "$label Super+Left" left 0
	keys -M logo -k Left -m logo
	check_snap "$id" "$label Super+Left again" left 1
	keys -M logo -k Left -m logo
	check_snap "$id" "$label Super+Left third" left 2
	keys -M logo -k Left -m logo
	check_snap "$id" "$label Super+Left cycles back" left 0
	keys -M logo -k Right -m logo
	assert_soon "W($id)['snapped'] is None and box(W($id)['content'])==$geo0" "$label opposite side (Super+Right) restores the old geometry $geo0"

	keys -M logo -k Right -m logo
	check_snap "$id" "$label Super+Right" right 0
	keys -M logo -k Right -m logo
	check_snap "$id" "$label Super+Right again" right 1
	keys -M logo -k Right -m logo
	check_snap "$id" "$label Super+Right third" right 2
	keys -M logo -k Left -m logo
	assert_soon "W($id)['snapped'] is None and box(W($id)['content'])==$geo0" "$label Super+Left on a right snap restores"

	# Super+Down on a snapped window restores (does not minimize).
	keys -M logo -k Left -m logo
	check_snap "$id" "$label re-snap" left 0
	keys -M logo -k Down -m logo
	assert_soon "W($id)['snapped'] is None and not W($id)['minimized'] and box(W($id)['content'])==$geo0" "$label Super+Down on a snapped window restores, not minimizes"

	# Maximize / restore / minimize ladder.
	local bar; bar=$(BAR_EXPR "$id")
	local max="box(W($id)['content'])==(usable['x']+1, usable['y']+$bar+1, usable['width']-2, usable['height']-$bar-2)"
	keys -M logo -k Up -m logo
	assert_soon "W($id)['maximized'] and $max" "$label Super+Up maximizes"
	keys -M logo -k Up -m logo
	sleep 0.4
	assert_json "W($id)['maximized'] and $max" "$label Super+Up on a maximized window does nothing"
	keys -M logo -k Left -m logo
	check_snap "$id" "$label Super+Left from maximized" left 0
	keys -M logo -k Up -m logo
	assert_soon "W($id)['maximized'] and W($id)['snapped'] is None and $max" "$label Super+Up from a snap maximizes"
	keys -M logo -k Down -m logo
	assert_soon "not W($id)['maximized'] and box(W($id)['content'])==$geo0" "$label Super+Down on maximized restores the pre-snap geometry"
	keys -M logo -k Down -m logo
	assert_soon "W($id)['minimized']" "$label Super+Down on a normal window still minimizes"
	ctl focus "$id" >/dev/null
	assert_soon "not W($id)['minimized'] and W($id)['focused']" "$label focus brings it back"
}

scenario_wm_snap() {
	open_ssd_app || skip "neither foot nor xterm available"
	local id=$WID
	wm_snap_checks "$id" "$SSD_APP(ssd)"
	keys -M logo -k Left -m logo
	check_snap "$id" "$SSD_APP final" left 0
	snap
}

scenario_wm_snap_csd() {
	open_app gtk Probe $PROBE || return
	local id=$WID
	ctl focus "$id" >/dev/null; wait_json "W($id)['focused']" 3
	keys -M logo -k Left -m logo
	check_snap "$id" "probe(csd) Super+Left" left 0
	assert_soon "W($id)['tiled']==7" "csd client was told it is tiled on left/top/bottom (WLR_EDGE 1|2|4)"
	assert_soon "box(W($id)['frame'])==$(snap_frame_expr left 0)" "csd frame still fits after the client committed"
	snap
	keys -M logo -k Right -m logo
	assert_soon "W($id)['snapped'] is None and W($id)['tiled']==0" "csd restore clears the tiled state"
	keys -M logo -k Right -m logo
	assert_soon "W($id)['tiled']==11" "csd right snap: tiled right/top/bottom (WLR_EDGE 1|2|8)"
	check_snap "$id" "probe(csd) Super+Right" right 0
}

scenario_wm_snap_x11() {
	[ -n "$XDISP" ] || skip "no XWayland"
	have xterm || skip "xterm not installed"
	open_app x xterm xterm || return
	wm_snap_checks "$WID" "xterm(x11)"
}

scenario_wm_drag_snap() {
	open_ssd_app || skip "neither foot nor xterm available"
	local id=$WID geo0 bar; bar=$(BAR_EXPR "$id")
	ctl focus "$id" >/dev/null; wait_json "W($id)['focused']" 3
	geo0=$(sj "box(W($id)['content'])")
	local right="usable['x']+usable['width']"

	# left edge: preview while hovering, snap on release
	ctl drag "$id" 0 400 >/dev/null
	sleep 0.4
	assert_json "W($id)['snapped'] is None" "still unsnapped while hovering the left edge"
	snap hover_left
	local half; half=$(sj "usable['x']+usable['width']//2")
	python3 - "$OUTDIR/${SCENARIO}__hover_left.png" "$(sj "usable['x']")" "$half" "$(sj "usable['y']+usable['height']//2")" <<'PY' || fail "no translucent preview rectangle on the left edge in the screenshot"
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
x0, x1, y = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
# the preview's 2px right edge is the skin accent at 85%: it stands out from
# the wallpaper just outside the preview, whatever the skin
n = 0
for y in range(y + 20, y + 60):
    edge, out = im.getpixel((x1 - 1, y)), im.getpixel((x1 + 6, y))
    n += sum(abs(a - b) for a, b in zip(edge, out)) > 40
sys.exit(0 if n >= 30 else 1)
PY
	ctl drag-release >/dev/null
	check_snap "$id" "drag to left edge" left 0

	# dragging the snapped window out restores its size
	ctl drag "$id" 600 300 >/dev/null
	assert_soon "W($id)['snapped'] is None and box(W($id)['content'])[2:]==$geo0[2:]" "dragging a snapped window restores its saved size"
	ctl drag "$id" 700 340 >/dev/null
	ctl drag-release >/dev/null
	assert_json "W($id)['snapped'] is None" "dropped mid-screen: no snap"

	# right edge
	ctl drag "$id" 5000 400 >/dev/null
	snap hover_right
	ctl drag-release >/dev/null
	check_snap "$id" "drag to right edge" right 0

	# top edge maximizes
	ctl drag "$id" 700 300 >/dev/null
	ctl drag "$id" 700 0 >/dev/null
	snap hover_top
	ctl drag-release >/dev/null
	local max="box(W($id)['content'])==(usable['x']+1, usable['y']+$bar+1, usable['width']-2, usable['height']-$bar-2)"
	assert_soon "W($id)['maximized'] and W($id)['snapped'] is None and $max" "drag to the top edge maximizes"

	# dragging the maximized window restores it (existing logic) and a drop mid-screen leaves it normal
	ctl drag "$id" 600 300 >/dev/null
	ctl drag-release >/dev/null
	assert_soon "not W($id)['maximized'] and not W($id)['snapped']" "dragging a maximized window restores it"

	# the snapped state survives layer changes: ultimitctl snap + state JSON
	ctl snap "$id" left >/dev/null
	check_snap "$id" "ctl snap left" left 0
	ctl snap "$id" restore >/dev/null
	assert_soon "W($id)['snapped'] is None" "ctl snap restore"
}

scenario_wm_show_desktop() {
	open_app wl foot foot || return; local a=$WID
	open_app wl foot foot || return; local b=$WID
	open_app wl foot foot || return; local c=$WID
	ctl minimize "$b" >/dev/null   # already minimized: must stay minimized after the round trip
	assert_soon "W($b)['minimized']" "b minimized beforehand"
	ctl focus "$c" >/dev/null; wait_json "W($c)['focused']" 3
	local order; order=$(sj "[w['id'] for w in wins]")
	keys -M logo -k d -m logo
	assert_soon "W($a)['minimized'] and W($c)['minimized']" "Super+D minimizes every window"
	keys -M logo -k d -m logo
	assert_soon "not W($a)['minimized'] and not W($c)['minimized'] and W($b)['minimized']" "second Super+D restores the same set (not the one minimized earlier)"
	assert_soon "W($c)['focused']" "previously focused window has focus again"
	assert_json "[w['id'] for w in wins if not w['minimized']]==[x for x in $order if x!=$b]" "stacking order preserved"
	snap
	# something new opened in between is hidden by the next press
	keys -M logo -k d -m logo
	assert_soon "W($a)['minimized'] and W($c)['minimized']" "Super+D again hides them"
	ctl focus "$a" >/dev/null
	assert_soon "not W($a)['minimized']" "restore one window by hand"
	keys -M logo -k d -m logo
	assert_soon "W($a)['minimized']" "Super+D with something visible hides it again"
	keys -M logo -k d -m logo
	assert_soon "not W($a)['minimized'] and not W($c)['minimized']" "and the next press brings back the whole set"
}

scenario_wm_alttab() {
	open_app wl foot foot || return; local a=$WID
	open_app wl foot foot || return; local b=$WID
	open_app wl foot foot || return; local c=$WID
	ctl focus "$a" >/dev/null; ctl focus "$b" >/dev/null; ctl focus "$c" >/dev/null
	assert_soon "[w['id'] for w in wins][:3]==[$c,$b,$a]" "MRU order is c b a"
	local ev="$RUNDIR/events.log"
	: >"$ev"
	"$ROOT/shell/bin/ultimitctl" events >>"$ev" 2>&1 &
	local epid=$!
	trap 'kill $epid 2>/dev/null' EXIT
	sleep 0.5

	# quick Alt+Tab: previous window, overlay never announced
	keys -M alt -k Tab -m alt
	assert_soon "W($b)['focused']" "quick Alt+Tab focuses the previous window (b)"
	assert_soon "[w['id'] for w in wins][:3]==[$b,$c,$a]" "MRU now b c a"
	sleep 0.3
	if grep -q '"action":"show"' "$ev"; then fail "quick Alt+Tab flashed the overlay"; fi

	# Tab Tab: highlight moves to the third entry (a) and releasing focuses it
	keys -M alt -k Tab -k Tab -m alt
	assert_soon "W($a)['focused']" "Alt+Tab Tab goes two back (a)"
	assert_soon "[w['id'] for w in wins][:3]==[$a,$b,$c]" "MRU now a b c"

	# Shift+Tab goes to the least recently used window
	keys -M alt -M shift -k Tab -m shift -m alt
	assert_soon "W($c)['focused']" "Alt+Shift+Tab focuses the oldest (c)"

	# Escape cancels: focus unchanged
	keys -M alt -k Tab -k Escape -m alt
	sleep 0.4
	assert_json "W($c)['focused']" "Alt+Tab, Escape: focus unchanged"

	# slow Alt+Tab: overlay shown with the list, the highlight moves, hidden on release
	: >"$ev"
	keys -M alt -k Tab -s 500 -k Tab -s 200 -m alt
	assert_soon "len(wins)==3" "still three windows" 2
	sleep 0.3
	grep -q '"action":"show"' "$ev" || fail "slow Alt+Tab never announced the overlay"
	grep -q '"action":"move"' "$ev" || fail "second Tab did not announce a move"
	grep -q '"action":"hide"' "$ev" || fail "release did not hide the overlay"
	python3 - "$ev" <<'PY' || fail "overlay event payload wrong (need 3 items, current window first, start index 1)"
import json, sys
evs = [json.loads(l) for l in open(sys.argv[1]) if l.startswith('{"event"')]
show = next(e for e in evs if e["action"] == "show")
sys.exit(0 if len(show["items"]) == 3 and show["index"] == 1 and show["items"][0]["app_id"] else 1)
PY
	# a minimized window can be chosen: it is restored and focused
	local last; last=$(sj "wins[-1]['id']")
	ctl minimize "$last" >/dev/null
	assert_soon "W($last)['minimized'] and not W($last)['focused']" "oldest window ($last) minimized in the background"
	keys -M alt -M shift -k Tab -m shift -m alt
	assert_soon "not W($last)['minimized'] and W($last)['focused']" "Alt+Shift+Tab onto a minimized window restores and focuses it"

	# Super+Tab does the same
	local before; before=$(sj "wins[1]['id']")
	keys -M logo -k Tab -m logo
	assert_soon "W($before)['focused']" "Super+Tab switches like Alt+Tab"

	kill $epid 2>/dev/null
}

scenario_wm_alttab_shot() {
	open_app gtk Probe $PROBE || return
	open_app wl foot foot || return
	open_app wl foot foot || return
	open_app wl foot foot || return
	keys -M alt -k Tab -s 2500 -k Tab -m alt &
	local kpid=$!
	sleep 1.4
	grim "$OUTDIR/${SCENARIO}__overlay.png"
	assert_json "layer('ultimit-alttab') and layer('ultimit-alttab')['mapped']" "overlay layer surface is mapped while Alt is held"
	local box; box=$(sj "layer('ultimit-alttab')['box']")
	note "overlay box $box"
	assert_json "layer('ultimit-alttab')['layer']==3" "overlay is on the overlay layer"
	wait $kpid
	sleep 1
	assert_soon "not layer('ultimit-alttab') or not layer('ultimit-alttab')['mapped']" "overlay unmapped after release"
}

scenario_wm_keys() {
	local out; out=$(ctl keys) || { fail "ultimitctl keys failed"; return; }
	echo "$out" >"$OUTDIR/${SCENARIO}__keys.json"
	python3 - "$OUTDIR/${SCENARIO}__keys.json" <<'PY' || fail "keys JSON missing expected bindings"
import json, sys
k = json.load(open(sys.argv[1]))["bindings"]
by = {b["keys"]: b for b in k}
need = ["Alt+Tab", "Super+Tab", "Super+Left", "Super+Right", "Super+Up", "Super+Down", "Super+D", "Super+E",
        "Super+R", "Super+L", "Super+Shift+S", "PrtSc", "Ctrl+Alt+T", "Alt+F4", "Volume up key", "Super+V", "Super+/", "Super+Shift+R", "Super+Alt+R"]
missing = [n for n in need if n not in by]
print(missing)
sys.exit(1 if missing else 0)
PY
	assert_json "True" "keys ok"
}
