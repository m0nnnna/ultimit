# Screenshot key and overall health.

scenario_screenshot_key() {
	have wl-copy || note "wl-copy missing; the script may fail after saving"
	local dir; dir="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Screenshots"
	mkdir -p "$dir"
	local before; before=$(ls "$dir" 2>/dev/null)
	keys -k Print
	local new= end=$((SECONDS + 15)) f
	while [ $SECONDS -lt $end ]; do
		for f in "$dir"/Ultimit_*.png; do
			[ -e "$f" ] || continue
			grep -qxF "$(basename "$f")" <<<"$before" || new=$f
		done
		[ -n "$new" ] && break
		sleep 0.3
	done
	if [ -z "$new" ]; then
		fail "no new file in $dir after pressing Print"
	else
		sleep 1 # let grim finish writing
		assert_eq "$(head -c 4 "$new" | tail -c 3)" "PNG" "screenshot is a PNG"
		assert_json "$(stat -c %s "$new")>5000" "screenshot is not empty"
		python3 - "$new" <<'PY' || fail "screenshot size is not the output size"
import sys
from PIL import Image
assert Image.open(sys.argv[1]).size == (1280, 720)
PY
		rm -f -- "$new" # never leave test files in the user's folder
		note "removed $(basename "$new")"
	fi
}

scenario_no_crash() {
	assert_eq "$(kill -0 "$(cat "$DEVBOX_STATE/pid")" 2>/dev/null && echo alive || echo dead)" alive "compositor alive"
	assert_json "layer('ultimit-rail') and layer('ultimit-ticker')" "shell layers still present"
	local log="$RUNDIR/log.txt" bad xcb
	sed 's/\x1b\[[0-9;]*m//g' "$DEVBOX_STATE/log" >"$log"
	cp "$log" "$OUTDIR/devbox.log"
	# Known noise: xkbcomp warnings, EGL info, and wlroots' xcb errors for
	# requests that race an X11 window's destruction (code Window).
	xcb=$(grep -c 'xwm.c.*xcb error.*code Window' "$log")
	bad=$(grep -E 'Assert|Segmentation|ERROR|Aborted|core dumped' "$log" \
		| grep -vE 'xkbcomp|xkb|EGL|xcb error: op [A-Za-z]+ \(no minor\), code Window' || true)
	[ -z "$bad" ] || fail "log has errors: $(echo "$bad" | head -n2 | tr '\n' '|')"
	[ "$xcb" -eq 0 ] || note "$xcb benign xcb 'code Window' errors in log (X window destroyed mid-request)"
}
