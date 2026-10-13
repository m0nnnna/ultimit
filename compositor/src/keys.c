/*
 * keys.c: every compositor keybinding, in one table.
 *
 * To add or change a shortcut edit `bindings` below; handling, the cheat
 * sheet (`ultimitctl keys`) and docs all come from it. Matching:
 *   - the modifiers must be exactly those listed (Shift/Ctrl/Alt/Super; Caps
 *     and Num Lock are ignored), unless KB_ANY_MODS;
 *   - the key matches case-insensitively (`sym`), or `sym2` (Shift+Tab can
 *     arrive as ISO_Left_Tab);
 *   - KB_ALWAYS bindings also work over the lock screen (media keys);
 *   - KB_DOC rows are not matched here: they document behaviour implemented
 *     elsewhere (Super tap, mouse gestures, VT switching).
 * The first matching row wins.
 *
 * While the Alt+Tab switcher is open its own keys (Tab, Shift+Tab, arrows,
 * Escape) are handled by alttab.c before this table is consulted.
 */

#include <stdlib.h>
#include <ctype.h>
#include <stdio.h>
#include <string.h>
#include <xkbcommon/xkbcommon.h>
#include "server.h"
#include "json.h"

enum act {
	ACT_NONE,
	ACT_QUIT,
	ACT_TERMINAL,
	ACT_SPAWN,
	ACT_LAUNCHER,
	ACT_LOCK,
	ACT_ALTTAB_NEXT,
	ACT_ALTTAB_PREV,
	ACT_CLOSE,
	ACT_FULLSCREEN,
	ACT_MAXIMIZE_TOGGLE,
	ACT_MAXIMIZE,
	ACT_SNAP_LEFT,
	ACT_SNAP_RIGHT,
	ACT_DOWN,
	ACT_SHOW_DESKTOP,
};

#define KB_ANY_MODS (1 << 0)
#define KB_ALWAYS   (1 << 1)
#define KB_DOC      (1 << 2)

#define SHIFT WLR_MODIFIER_SHIFT
#define CTRL  WLR_MODIFIER_CTRL
#define ALT   WLR_MODIFIER_ALT
#define SUPER WLR_MODIFIER_LOGO

struct binding {
	uint32_t mods;
	xkb_keysym_t sym, sym2;
	enum act act;
	const char *arg;        /* ACT_SPAWN: the command */
	const char *label;      /* overrides the generated "Super+Left" for KB_DOC rows */
	const char *category;
	const char *action;     /* stable name for the cheat sheet */
	const char *desc;
	unsigned flags;
};

static const struct binding bindings[] = {
	/* ---- windows ---- */
	{ ALT, XKB_KEY_Tab, 0, ACT_ALTTAB_NEXT, NULL, NULL, "Windows", "switch-next",
		"Switch windows (hold Alt, Tab to step, release to go)", 0 },
	{ ALT | SHIFT, XKB_KEY_Tab, XKB_KEY_ISO_Left_Tab, ACT_ALTTAB_PREV, NULL, NULL, "Windows",
		"switch-prev", "Switch windows, backwards", 0 },
	{ SUPER, XKB_KEY_Tab, 0, ACT_ALTTAB_NEXT, NULL, NULL, "Windows", "switch-next",
		"Switch windows (same as Alt+Tab)", 0 },
	{ SUPER | SHIFT, XKB_KEY_Tab, XKB_KEY_ISO_Left_Tab, ACT_ALTTAB_PREV, NULL, NULL, "Windows",
		"switch-prev", "Switch windows, backwards", 0 },
	{ 0, XKB_KEY_Escape, 0, ACT_NONE, NULL, "Escape", "Windows", "switch-cancel",
		"Cancel the window switcher (while it is open)", KB_DOC },
	{ ALT, XKB_KEY_F4, 0, ACT_CLOSE, NULL, NULL, "Windows", "close", "Close window", 0 },
	{ SUPER, XKB_KEY_Left, 0, ACT_SNAP_LEFT, NULL, NULL, "Windows", "snap-left",
		"Snap left (repeat: 1/2, 1/3, 2/3; Super+Right restores)", 0 },
	{ SUPER, XKB_KEY_Right, 0, ACT_SNAP_RIGHT, NULL, NULL, "Windows", "snap-right",
		"Snap right (repeat: 1/2, 1/3, 2/3; Super+Left restores)", 0 },
	{ SUPER, XKB_KEY_Up, 0, ACT_MAXIMIZE, NULL, NULL, "Windows", "maximize", "Maximize", 0 },
	{ SUPER, XKB_KEY_Down, 0, ACT_DOWN, NULL, NULL, "Windows", "restore-minimize",
		"Restore a snapped/maximized window, otherwise minimize", 0 },
	{ ALT, XKB_KEY_F10, 0, ACT_MAXIMIZE_TOGGLE, NULL, NULL, "Windows", "maximize-toggle",
		"Maximize / restore", 0 },
	{ ALT, XKB_KEY_F11, 0, ACT_FULLSCREEN, NULL, NULL, "Windows", "fullscreen", "Fullscreen", 0 },
	{ SUPER, XKB_KEY_f, 0, ACT_FULLSCREEN, NULL, NULL, "Windows", "fullscreen", "Fullscreen", 0 },
	{ SUPER, XKB_KEY_d, 0, ACT_SHOW_DESKTOP, NULL, NULL, "Windows", "show-desktop",
		"Show desktop (minimize all; press again to restore)", 0 },
	{ 0, 0, 0, ACT_NONE, NULL, "Drag titlebar to a screen edge", "Windows", "drag-snap",
		"Snap to that half; the top edge maximizes", KB_DOC },
	{ 0, 0, 0, ACT_NONE, NULL, "Alt/Super + left drag", "Windows", "drag-move",
		"Move a window from anywhere", KB_DOC },
	{ 0, 0, 0, ACT_NONE, NULL, "Alt/Super + right drag", "Windows", "drag-resize",
		"Resize a window from anywhere", KB_DOC },

	/* ---- apps and session ---- */
	{ CTRL | ALT, XKB_KEY_t, 0, ACT_TERMINAL, NULL, NULL, "Apps", "terminal", "Open a terminal", 0 },
	{ SUPER, XKB_KEY_e, 0, ACT_SPAWN, "ultimit-data", NULL, "Apps", "data",
		"Open DATA (files)", 0 },
	{ SUPER, XKB_KEY_r, 0, ACT_LAUNCHER, NULL, NULL, "Apps", "launcher", "Open the launcher", 0 },
	{ SUPER, XKB_KEY_v, 0, ACT_SPAWN, "ultimit-clipboard", NULL, "Apps", "clipboard",
		"Clipboard history (Enter pastes, P pins)", 0 },
	{ SUPER, XKB_KEY_slash, 0, ACT_SPAWN, "ultimit-shortcuts", NULL, "Apps", "shortcuts",
		"Show these keyboard shortcuts", 0 },
	{ SUPER, XKB_KEY_Super_L, 0, ACT_NONE, NULL, "Super (tap)", "Apps", "launcher-tap",
		"Open the launcher when Super is tapped on its own", KB_DOC },
	{ SUPER, XKB_KEY_l, 0, ACT_LOCK, NULL, NULL, "Session", "lock", "Lock the screen", 0 },
	{ SUPER | SHIFT, XKB_KEY_s, 0, ACT_SPAWN, "ultimit-screenshot area", NULL, "Session",
		"screenshot-area", "Screenshot a region", 0 },
	{ SUPER | SHIFT, XKB_KEY_r, 0, ACT_SPAWN, "ultimit-screenshot record-area", NULL, "Session",
		"record-area", "Record a region (press again to stop and save)", 0 },
	{ SUPER | ALT, XKB_KEY_r, 0, ACT_SPAWN, "ultimit-screenshot record-full", NULL, "Session",
		"record-full", "Record the screen (press again to stop and save)", 0 },
	{ 0, XKB_KEY_Print, 0, ACT_SPAWN, "ultimit-screenshot full", NULL, "Session",
		"screenshot-full", "Screenshot the screen", KB_ANY_MODS },
	{ CTRL | ALT, XKB_KEY_BackSpace, 0, ACT_QUIT, NULL, NULL, "Session", "quit",
		"Quit Ultimit (log out)", 0 },
	{ CTRL | ALT, 0, 0, ACT_NONE, NULL, "Ctrl+Alt+F1..F12", "Session", "vt",
		"Switch virtual terminal", KB_DOC },

	/* ---- media keys (work over the lock screen too) ---- */
	{ 0, XKB_KEY_XF86AudioRaiseVolume, 0, ACT_SPAWN, "ultimit-media volume up", NULL, "Media",
		"volume-up", "Volume up", KB_ANY_MODS | KB_ALWAYS },
	{ 0, XKB_KEY_XF86AudioLowerVolume, 0, ACT_SPAWN, "ultimit-media volume down", NULL, "Media",
		"volume-down", "Volume down", KB_ANY_MODS | KB_ALWAYS },
	{ 0, XKB_KEY_XF86AudioMute, 0, ACT_SPAWN, "ultimit-media volume mute", NULL, "Media",
		"volume-mute", "Mute", KB_ANY_MODS | KB_ALWAYS },
	{ 0, XKB_KEY_XF86AudioMicMute, 0, ACT_SPAWN, "ultimit-media mic mute", NULL, "Media",
		"mic-mute", "Mute microphone", KB_ANY_MODS | KB_ALWAYS },
	{ 0, XKB_KEY_XF86MonBrightnessUp, 0, ACT_SPAWN, "ultimit-media brightness up", NULL, "Media",
		"brightness-up", "Brightness up", KB_ANY_MODS | KB_ALWAYS },
	{ 0, XKB_KEY_XF86MonBrightnessDown, 0, ACT_SPAWN, "ultimit-media brightness down", NULL,
		"Media", "brightness-down", "Brightness down", KB_ANY_MODS | KB_ALWAYS },
	{ 0, XKB_KEY_XF86AudioPlay, 0, ACT_SPAWN, "ultimit-media play-pause", NULL, "Media",
		"play-pause", "Play / pause", KB_ANY_MODS | KB_ALWAYS },
	{ 0, XKB_KEY_XF86AudioPause, 0, ACT_SPAWN, "ultimit-media play-pause", NULL, "Media",
		"play-pause", "Play / pause", KB_ANY_MODS | KB_ALWAYS },
	{ 0, XKB_KEY_XF86AudioNext, 0, ACT_SPAWN, "ultimit-media next", NULL, "Media",
		"next-track", "Next track", KB_ANY_MODS | KB_ALWAYS },
	{ 0, XKB_KEY_XF86AudioPrev, 0, ACT_SPAWN, "ultimit-media prev", NULL, "Media",
		"prev-track", "Previous track", KB_ANY_MODS | KB_ALWAYS },
};

#define N_BINDINGS (sizeof(bindings) / sizeof(bindings[0]))
#define MOD_MASK (SHIFT | CTRL | ALT | SUPER)

/* ---- actions ---------------------------------------------------------------- */

static void snap_key(struct ul_view *view, enum ul_snap side) {
	if (!view || view->fullscreen) {
		return;
	}
	if (view->snapped == side) {
		view_snap(view, side, (view->snap_step + 1) % UL_SNAP_STEPS);
	} else if (view->snapped) {
		view_restore(view); /* the opposite side */
	} else {
		view_snap(view, side, 0);
	}
}

static void run(struct ul_server *server, const struct binding *b, uint32_t mods) {
	struct ul_view *view = server->focused_view;
	switch (b->act) {
	case ACT_QUIT:
		wl_display_terminate(server->display);
		break;
	case ACT_TERMINAL: {
		const char *term = getenv("ULTIMIT_TERMINAL");
		server_spawn(term ? term : "foot || kitty || ptyxis --new-window || xterm");
		break;
	}
	case ACT_SPAWN:
		server_spawn(b->arg);
		break;
	case ACT_LAUNCHER:
		keys_super_tap(server);
		break;
	case ACT_LOCK:
		server_spawn("ultimit-lock");
		break;
	case ACT_ALTTAB_NEXT:
		alttab_step(server, mods, 1);
		break;
	case ACT_ALTTAB_PREV:
		alttab_step(server, mods, -1);
		break;
	case ACT_CLOSE:
		if (view) view_close(view);
		break;
	case ACT_FULLSCREEN:
		if (view) view_set_fullscreen(view, !view->fullscreen);
		break;
	case ACT_MAXIMIZE_TOGGLE:
		if (view) view_set_maximized(view, !view->maximized);
		break;
	case ACT_MAXIMIZE:
		if (view && !view->fullscreen && !view->maximized) view_set_maximized(view, true);
		break;
	case ACT_SNAP_LEFT:
		snap_key(view, UL_SNAP_LEFT);
		break;
	case ACT_SNAP_RIGHT:
		snap_key(view, UL_SNAP_RIGHT);
		break;
	case ACT_DOWN:
		if (view && !view->fullscreen && (view->snapped || view->maximized)) {
			view_restore(view);
		} else if (view) {
			view_set_minimized(view, true);
		}
		break;
	case ACT_SHOW_DESKTOP:
		view_show_desktop(server);
		break;
	case ACT_NONE:
		break;
	}
}

/* Opens the launcher (the Super tap and Super+R). */
void keys_super_tap(struct ul_server *server) {
	const char *cmd = getenv("ULTIMIT_LAUNCHER");
	server_spawn(cmd ? cmd : "ultimit-launcher");
}

/* Returns true if the key press was consumed. */
bool keys_handle(struct ul_server *server, uint32_t mods, xkb_keysym_t sym) {
	/* Ctrl+Alt+Fn arrives as XF86Switch_VT_n. */
	if (sym >= XKB_KEY_XF86Switch_VT_1 && sym <= XKB_KEY_XF86Switch_VT_12) {
		if (server->session) {
			wlr_session_change_vt(server->session, sym - XKB_KEY_XF86Switch_VT_1 + 1);
		}
		return true;
	}
	/* Nothing but the media keys may get past the lock screen. */
	if (!server->locked && alttab_active(server) && alttab_key(server, sym)) {
		return true;
	}
	mods &= MOD_MASK;
	xkb_keysym_t lower = xkb_keysym_to_lower(sym);
	for (size_t i = 0; i < N_BINDINGS; i++) {
		const struct binding *b = &bindings[i];
		if ((b->flags & KB_DOC) || (server->locked && !(b->flags & KB_ALWAYS))) {
			continue;
		}
		if (!(b->flags & KB_ANY_MODS) && mods != b->mods) {
			continue;
		}
		if (lower != b->sym && sym != b->sym2) {
			continue;
		}
		run(server, b, mods);
		return true;
	}
	return false;
}

/* ---- `ultimitctl keys` --------------------------------------------------------- */

/* What the key says on a keyboard, for keysym names that don't. */
static const char *friendly_key(const char *name) {
	static const struct { const char *sym, *label; } names[] = {
		{ "slash", "/" }, { "BackSpace", "Backspace" }, { "Print", "PrtSc" },
		{ "AudioRaiseVolume", "Volume up key" }, { "AudioLowerVolume", "Volume down key" },
		{ "AudioMute", "Mute key" }, { "AudioMicMute", "Mic mute key" },
		{ "MonBrightnessUp", "Brightness up key" }, { "MonBrightnessDown", "Brightness down key" },
		{ "AudioPlay", "Play key" }, { "AudioPause", "Pause key" },
		{ "AudioNext", "Next track key" }, { "AudioPrev", "Previous track key" },
	};
	for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
		if (strcmp(name, names[i].sym) == 0) return names[i].label;
	}
	return name;
}

static void combo_name(const struct binding *b, char *buf, size_t len) {
	if (b->label) {
		snprintf(buf, len, "%s", b->label);
		return;
	}
	buf[0] = '\0';
	if (b->mods & SUPER) strncat(buf, "Super+", len - strlen(buf) - 1);
	if (b->mods & CTRL) strncat(buf, "Ctrl+", len - strlen(buf) - 1);
	if (b->mods & ALT) strncat(buf, "Alt+", len - strlen(buf) - 1);
	if (b->mods & SHIFT) strncat(buf, "Shift+", len - strlen(buf) - 1);
	char key[64] = "";
	xkb_keysym_get_name(b->sym, key, sizeof(key));
	if (key[0] && !key[1]) key[0] = toupper((unsigned char)key[0]);
	if (strncmp(key, "XF86", 4) == 0) memmove(key, key + 4, strlen(key + 4) + 1);
	strncat(buf, friendly_key(key), len - strlen(buf) - 1);
}

void keys_write_json(struct out *o) {
	put(o, "{\"bindings\":[");
	bool first = true;
	for (size_t i = 0; i < N_BINDINGS; i++) {
		const struct binding *b = &bindings[i];
		char combo[128];
		combo_name(b, combo, sizeof(combo));
		put(o, "%s{\"keys\":", first ? "" : ",");
		put_str(o, combo);
		put(o, ",\"mods\":[");
		const char *sep = "";
		static const struct { uint32_t bit; const char *name; } names[] = {
			{ CTRL, "ctrl" }, { ALT, "alt" }, { SHIFT, "shift" }, { SUPER, "super" },
		};
		for (size_t m = 0; m < 4; m++) {
			if (b->mods & names[m].bit) {
				put(o, "%s\"%s\"", sep, names[m].name);
				sep = ",";
			}
		}
		char key[64] = "";
		if (b->sym) xkb_keysym_get_name(b->sym, key, sizeof(key));
		put(o, "],\"key\":");
		if (b->label || !b->sym) put(o, "null"); else put_str(o, key);
		put(o, ",\"action\":");
		put_str(o, b->action);
		put(o, ",\"category\":");
		put_str(o, b->category);
		put(o, ",\"description\":");
		put_str(o, b->desc);
		put(o, ",\"gesture\":%s}", (b->flags & KB_DOC) ? "true" : "false");
		first = false;
	}
	put(o, "]}");
}
