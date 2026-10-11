/*
 * alttab.c: the Windows-style window switcher.
 *
 * Alt+Tab (or Super+Tab) snapshots the windows in most-recently-focused
 * order (the current window first, minimized ones included) and highlights
 * the second. Each further Tab moves the highlight (Shift+Tab goes back,
 * Left/Right too, Escape cancels); releasing the modifier focuses the
 * highlighted window, un-minimizing it if needed.
 *
 * The overlay is drawn by the shell (shell/components/AltTab.qml). The
 * compositor pushes events over the control socket's event stream (a client
 * sends "subscribe" once and then receives one JSON line per event, see
 * ipc.c): {"event":"alttab","action":"show"|"move"|"hide",...}. That costs
 * one write per keypress, no process spawns. "show" is deferred by
 * UL_ALTTAB_DELAY_MS so a quick Alt+Tab+release switches without the
 * overlay flashing up.
 */

#include <string.h>
#include "server.h"

bool alttab_active(struct ul_server *server) {
	return server->alttab.active;
}

static void announce(struct ul_server *server, const char *action) {
	ipc_emit_alttab(server, action);
}

static int on_delay(void *data) {
	struct ul_server *server = data;
	if (server->alttab.active && !server->alttab.shown) {
		server->alttab.shown = true;
		announce(server, "show");
	}
	return 0;
}

static void stop(struct ul_server *server) {
	if (server->alttab.timer) {
		wl_event_source_timer_update(server->alttab.timer, 0);
	}
	bool was_shown = server->alttab.shown;
	server->alttab.active = false;
	server->alttab.shown = false;
	if (was_shown) {
		announce(server, "hide");
	}
}

void alttab_cancel(struct ul_server *server) {
	if (server->alttab.active) {
		stop(server);
	}
}

static void commit(struct ul_server *server) {
	struct ul_view *target = NULL;
	if (server->alttab.index >= 0 && server->alttab.index < server->alttab.count) {
		target = view_by_id(server, server->alttab.ids[server->alttab.index]);
	}
	stop(server);
	if (target && target->mapped) {
		view_focus(target);
	}
}

static void start(struct ul_server *server, uint32_t mods, int dir) {
	struct ul_view *view;
	int n = 0;
	wl_list_for_each(view, &server->views, link) {
		if (view->mapped && n < UL_ALTTAB_MAX) {
			server->alttab.ids[n++] = view->id;
		}
	}
	if (n < 2) {
		return; /* nothing to switch to */
	}
	server->alttab.count = n;
	server->alttab.index = dir > 0 ? 1 : n - 1;
	server->alttab.hold_mods = mods & (WLR_MODIFIER_ALT | WLR_MODIFIER_LOGO);
	server->alttab.active = true;
	server->alttab.shown = false;
	if (!server->alttab.timer) {
		server->alttab.timer = wl_event_loop_add_timer(
			wl_display_get_event_loop(server->display), on_delay, server);
	}
	wl_event_source_timer_update(server->alttab.timer, UL_ALTTAB_DELAY_MS);
}

/* A Tab press with Alt/Super held: open the switcher or move the highlight. */
void alttab_step(struct ul_server *server, uint32_t mods, int dir) {
	if (!server->alttab.active) {
		start(server, mods, dir);
		return;
	}
	int n = server->alttab.count;
	server->alttab.index = (server->alttab.index + dir + n) % n;
	if (server->alttab.shown) {
		announce(server, "move");
	}
}

/* Keys while the switcher is open. */
bool alttab_key(struct ul_server *server, xkb_keysym_t sym) {
	switch (sym) {
	case XKB_KEY_Tab:
	case XKB_KEY_Right:
		/* Shift+Tab is handled by the table (it arrives with Shift down). */
		alttab_step(server, server->alttab.hold_mods, 1);
		return true;
	case XKB_KEY_ISO_Left_Tab:
	case XKB_KEY_Left:
		alttab_step(server, server->alttab.hold_mods, -1);
		return true;
	case XKB_KEY_Escape:
		alttab_cancel(server);
		return true;
	}
	return false;
}

/* The modifier state changed: letting go of the held modifier commits. */
void alttab_modifiers(struct ul_server *server, uint32_t mods) {
	if (server->alttab.active &&
			(mods & server->alttab.hold_mods) != server->alttab.hold_mods) {
		commit(server);
	}
}

/* A window closed while the switcher was open. */
void alttab_view_gone(struct ul_server *server, unsigned id) {
	if (!server->alttab.active) {
		return;
	}
	int at = -1;
	for (int i = 0; i < server->alttab.count; i++) {
		if (server->alttab.ids[i] == id) at = i;
	}
	if (at < 0) {
		return;
	}
	memmove(&server->alttab.ids[at], &server->alttab.ids[at + 1],
		(server->alttab.count - at - 1) * sizeof(unsigned));
	server->alttab.count--;
	if (server->alttab.count < 2) {
		alttab_cancel(server);
		return;
	}
	if (server->alttab.index > at || server->alttab.index >= server->alttab.count) {
		server->alttab.index--;
	}
	if (server->alttab.index < 0) server->alttab.index = 0;
	if (server->alttab.shown) {
		announce(server, "show"); /* new list */
	}
}
