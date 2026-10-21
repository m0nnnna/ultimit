/*
 * textinput.c: text-input-v3, used here to pop the on-screen keyboard up.
 *
 * Apps enable a text input while one of their text fields has focus and
 * disable it when it loses focus. With an OSK running (ULTIMIT_OSK=1, a
 * phone), enable shows wvkbd and disable hides it again a moment later, so
 * moving between two fields doesn't flash it. Text itself still arrives
 * through wvkbd's virtual keyboard; there is no input method here.
 */

#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <wlr/types/wlr_text_input_v3.h>
#include <wlr/util/log.h>
#include "server.h"

struct ul_text_input {
	struct wlr_text_input_v3 *input;
	struct ul_server *server;
	struct wl_listener enable, disable, destroy;
};

static struct wl_event_source *hide_timer;
static int enabled_inputs;

static void osk_signal(bool show) {
	server_spawn(show ? "pkill --signal USR2 -x wvkbd-mobintl" :
		"pkill --signal USR1 -x wvkbd-mobintl");
}

static int hide_now(void *data) {
	if (enabled_inputs == 0) {
		osk_signal(false);
	}
	return 0;
}

static void ti_enable(struct wl_listener *listener, void *data) {
	struct ul_text_input *ti = wl_container_of(listener, ti, enable);
	enabled_inputs++;
	wl_event_source_timer_update(hide_timer, 0);
	osk_signal(true);
}

static void ti_disabled(struct ul_text_input *ti) {
	if (enabled_inputs > 0) {
		enabled_inputs--;
	}
	if (enabled_inputs == 0) {
		wl_event_source_timer_update(hide_timer, 300);
	}
}

static void ti_disable(struct wl_listener *listener, void *data) {
	struct ul_text_input *ti = wl_container_of(listener, ti, disable);
	ti_disabled(ti);
}

static void ti_destroy(struct wl_listener *listener, void *data) {
	struct ul_text_input *ti = wl_container_of(listener, ti, destroy);
	if (ti->input->current_enabled) {
		ti_disabled(ti);
	}
	wl_list_remove(&ti->enable.link);
	wl_list_remove(&ti->disable.link);
	wl_list_remove(&ti->destroy.link);
	free(ti);
}

/* A text input only works while it has "entered" the focused surface. */
static void ti_focus(struct wlr_text_input_v3 *input, struct wlr_surface *surface) {
	if (input->focused_surface == surface) {
		return;
	}
	if (input->focused_surface) {
		wlr_text_input_v3_send_leave(input);
	}
	if (surface && wl_resource_get_client(input->resource) ==
			wl_resource_get_client(surface->resource)) {
		wlr_text_input_v3_send_enter(input, surface);
	}
}

static void new_text_input(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, new_text_input);
	struct wlr_text_input_v3 *input = data;
	struct ul_text_input *ti = calloc(1, sizeof(*ti));
	if (!ti) {
		return;
	}
	ti->input = input;
	ti->server = server;
	ti->enable.notify = ti_enable;
	wl_signal_add(&input->events.enable, &ti->enable);
	ti->disable.notify = ti_disable;
	wl_signal_add(&input->events.disable, &ti->disable);
	ti->destroy.notify = ti_destroy;
	wl_signal_add(&input->events.destroy, &ti->destroy);
	ti_focus(input, server->seat->keyboard_state.focused_surface);
}

static void keyboard_focus_change(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, text_focus_change);
	struct wlr_seat_keyboard_focus_change_event *event = data;
	struct wlr_text_input_v3 *input;
	wl_list_for_each(input, &server->text_input->text_inputs, link) {
		ti_focus(input, event->new_surface);
	}
}

void text_input_init(struct ul_server *server) {
	const char *osk = getenv("ULTIMIT_OSK");
	if (!osk || strcmp(osk, "1") != 0) {
		return;
	}
	server->text_input = wlr_text_input_manager_v3_create(server->display);
	hide_timer = wl_event_loop_add_timer(wl_display_get_event_loop(server->display),
		hide_now, NULL);
	server->new_text_input.notify = new_text_input;
	wl_signal_add(&server->text_input->events.text_input, &server->new_text_input);
	server->text_focus_change.notify = keyboard_focus_change;
	wl_signal_add(&server->seat->keyboard_state.events.focus_change, &server->text_focus_change);
	wlr_log(WLR_INFO, "text-input-v3: the on-screen keyboard follows text fields");
}
