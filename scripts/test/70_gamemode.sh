# Game Mode: a fullscreen game quiets the desktop and restores it afterwards (shell/GameMode.qml).
# The devbox runs with a fake power-profiles-daemon (ULTIMIT_FAKE_PPD, set by scripts/test.sh).
# Needs foot (its app id is set with -a, so it can play a game, a browser or a video player).

gm() { qs -p "$ROOT/shell" ipc call gamemode "$@" 2>/dev/null; }
gm_field() { gm status | python3 -c "import json,sys; v=json.load(sys.stdin)['$1']; print(str(v).lower() if isinstance(v,bool) else v)"; }
gm_wait() { # FIELD VALUE [TIMEOUT_S]
	local end=$((SECONDS + ${3:-8}))
	while [ $SECONDS -lt $end ]; do
		[ "$(gm_field "$1" 2>/dev/null)" = "$2" ] && return 0
		sleep 0.3
	done
	return 1
}

scenario_gamemode() {
	have foot || skip "foot missing"
	have qs || skip "qs missing"
	[ -n "${ULTIMIT_FAKE_PPD:-}" ] || skip "no fake power daemon"
	gm_wait active false 15 || { fail "gamemode IPC not answering: $(gm status)"; return; }
	assert_eq "$(cat "$ULTIMIT_FAKE_PPD")" balanced "profile before"

	# A fullscreen browser or video player is not a game: the debounce time passes, nothing happens.
	local app
	for app in firefox mpv; do
		open_app wl "$app" foot -a "$app" || return; local b=$WID
		ctl fullscreen "$b" >/dev/null
		assert_soon "W($b)['fullscreen']" "$app fullscreen" 6 || return
		sleep 2.6
		assert_eq "$(gm_field active)" false "fullscreen $app does not start Game Mode"
		assert_eq "$(gm_field detected)" "" "$app not detected"
		close_win "$b"
	done

	# A fullscreen game does, after the debounce; the desktop pauses and the profile goes to performance.
	open_app wl steam_app_4242 foot -a steam_app_4242 || return; local g=$WID
	ctl fullscreen "$g" >/dev/null
	assert_soon "W($g)['fullscreen']" "game fullscreen" 6 || return
	assert_eq "$(gm_field active)" false "debounced: not instantly"
	gm_wait active true 8 || { fail "Game Mode did not engage: $(gm status)"; return; }
	assert_eq "$(gm_field reason)" fullscreen "reason"
	assert_eq "$(gm_field desktopPaused)" true "desktop animations paused"
	assert_eq "$(cat "$ULTIMIT_FAKE_PPD")" performance "performance profile while playing"
	snap game

	# Notifications are held, counted, and critical ones are not.
	qs -p "$ROOT/shell" ipc call toasts notify "While playing" "held" >/dev/null 2>&1
	assert_eq "$(gm_field held)" 1 "toast held"

	# The game ends (or crashes): everything comes back.
	close_win "$g"
	gm_wait active false 8 || { fail "Game Mode stuck after the game closed: $(gm status)"; return; }
	assert_eq "$(gm_field desktopPaused)" false "desktop animations resume"
	assert_eq "$(cat "$ULTIMIT_FAKE_PPD")" balanced "profile restored"
	assert_eq "$(python3 -c "import json,os; print(os.path.exists(os.environ['ULTIMIT_STATE_DIR']+'/gamemode.json'))")" False "state file removed"

	# Forcing, for testing: on / off / back to automatic.
	gm force on >/dev/null
	gm_wait active true 4 || { fail "force on"; return; }
	assert_eq "$(gm_field reason)" forced "forced reason"
	assert_eq "$(cat "$ULTIMIT_FAKE_PPD")" performance "profile when forced"
	gm force auto >/dev/null
	gm_wait active false 8 || { fail "back to automatic did not end it"; return; }
	assert_eq "$(cat "$ULTIMIT_FAKE_PPD")" balanced "profile restored after forcing"
}
