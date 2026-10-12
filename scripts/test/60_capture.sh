# Screen capture: ext-foreign-toplevel-list + ext-image-copy-capture, what
# xdg-desktop-portal-wlr uses for window and monitor sharing.

CAPTURE_PROBE="$ROOT/compositor/build/ul-capture-probe"

# capture_probe ARGS...: run the probe against the devbox only. Prints its
# one-line report; the exit status is the probe's.
capture_probe() {
	[ -n "$SOCK" ] && [ "$SOCK" != wayland-0 ] && [ "$SOCK" != "$LIVE_DISPLAY" ] || { echo "refusing: not the devbox socket"; return 2; }
	WAYLAND_DISPLAY="$SOCK" timeout 20 "$CAPTURE_PROBE" "$@"
}

# check_window_capture KIND APPMATCH LABEL CMD...
check_window_capture() {
	local kind=$1 app=$2 label=$3; shift 3
	open_app "$kind" "$app" "$@" || return
	local id=$WID appid out ppm="$OUTDIR/${SCENARIO}__$label.ppm"
	appid=$(wf "$id" "w['app_id']")
	assert_json "'$appid'!=''" "$label has an app_id"
	out=$(capture_probe "$appid" "$ppm" 2>&1) || { fail "$label: capture failed: $out"; return; }
	note "$label: $out"
	assert_eq "$(sed -n 's/^size \([0-9]*x[0-9]*\) .*/\1/p' <<<"$out")" \
		"$(wf "$id" "'%dx%d' % (w['content']['width'], w['content']['height'])")" \
		"$label capture size == window content size (no titlebar/border)"
	assert_json "$(sed -n 's/.* nonzero \([0-9]*\) .*/\1/p' <<<"$out")>0" "$label capture is not all zero"
	close_win "$id" || fail "$label did not close"
	# The toplevel is gone from the list now: nothing to capture.
	capture_probe "$appid" >/dev/null 2>&1 && fail "$label: still capturable after close"
}

scenario_capture_window() {
	[ -x "$CAPTURE_PROBE" ] || skip "ul-capture-probe not built"
	check_window_capture gtk Probe wayland-window $PROBE
	if have xmessage && [ -n "${XDISP:-}" ]; then
		check_window_capture x Xmessage x11-window xmessage -geometry 400x150 capture-test
	else
		note "skipped x11 window (no xmessage / XWayland)"
	fi
}

scenario_capture_output() {
	[ -x "$CAPTURE_PROBE" ] || skip "ul-capture-probe not built"
	open_app gtk Probe $PROBE || return
	local out
	out=$(capture_probe --output "$OUTDIR/${SCENARIO}.ppm" 2>&1) || { fail "output capture failed: $out"; return; }
	note "$out"
	assert_eq "$(sed -n 's/^size \([0-9]*x[0-9]*\) .*/\1/p' <<<"$out")" \
		"$(sj "'%dx%d' % (full['width'], full['height'])" 2>/dev/null)" "capture size == output size"
	assert_json "$(sed -n 's/.* nonzero \([0-9]*\) .*/\1/p' <<<"$out")>0" "output capture is not all zero"
}

# A started session keeps getting frames, and follows the window's size.
scenario_capture_stream() {
	[ -x "$CAPTURE_PROBE" ] || skip "ul-capture-probe not built"
	open_app gtk Probe $PROBE || return
	local id=$WID appid log="$RUNDIR/stream.txt" pid
	appid=$(wf "$id" "w['app_id']")
	[ -n "$SOCK" ] && [ "$SOCK" != wayland-0 ] && [ "$SOCK" != "$LIVE_DISPLAY" ] || { fail "not the devbox socket"; return; }
	WAYLAND_DISPLAY="$SOCK" ULCP_STREAM_MS=6000 timeout 20 "$CAPTURE_PROBE" "$appid" >"$log" 2>&1 &
	pid=$!
	sleep 1.5
	ctl resize "$id" 640 420 >/dev/null
	wait_json "W($id)['content']['width']==640 and W($id)['content']['height']==420" 6 || note "window did not resize to 640x420"
	wait "$pid" || fail "stream probe failed: $(tail -n2 "$log" | tr '\n' ' ')"
	note "frames: $(grep -c '^size' "$log"), sizes: $(sed -n 's/^size \([0-9x]*\) .*/\1/p' "$log" | uniq | paste -sd' ')"
	assert_json "$(grep -c '^size 800x560' "$log")>=1" "frames at the original size"
	assert_json "$(grep -c "^size $(wf "$id" "'%dx%d' % (w['content']['width'], w['content']['height'])") " "$log")>=1" "frames at the resized size"
}
