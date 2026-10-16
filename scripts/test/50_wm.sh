# Windows-style window management: Super+D show desktop, and the keybinding list.
# Needs foot.

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
