/*
 * lock.c: screen locking (ext-session-lock-v1) and idle (ext-idle-notify-v1,
 * idle-inhibit-v1).
 *
 * The lock screen itself is a Quickshell client. The compositor's job is to
 * make the lock trustworthy: while locked, a solid cover hides everything,
 * only lock surfaces get input, and if the lock client crashes the session
 * stays covered and locked until a new lock client unlocks it.
 */

#include <stdlib.h>
#include <string.h>
#include <wlr/types/wlr_idle_inhibit_v1.h>
#include <wlr/types/wlr_idle_notify_v1.h>
#include <wlr/types/wlr_session_lock_v1.h>
#include "server.h"
#include "theme.h"

struct ul_lock_surface {
	struct ul_server *server;
	struct wlr_session_lock_surface_v1 *lock_surface;
	struct wlr_scene_tree *tree;
	struct wl_listener map;
	struct wl_listener destroy;
};

static void focus_lock_surface(struct ul_server *server, struct wlr_surface *surface) {
	struct wlr_keyboard *keyboard = wlr_seat_get_keyboard(server->seat);
	wlr_seat_keyboard_notify_enter(server->seat, surface,
		keyboard ? keyboard->keycodes : NULL, keyboard ? keyboard->num_keycodes : 0,
		keyboard ? &keyboard->modifiers : NULL);
}

/* Size and place every lock surface on its output (outputs can change while
 * locked). */
void lock_arrange(struct ul_server *server) {
	struct wlr_box box;
	wlr_output_layout_get_box(server->output_layout, NULL, &box);
	wlr_scene_node_set_position(&server->lock_cover->node, box.x, box.y);
	wlr_scene_rect_set_size(server->lock_cover, box.width, box.height);
	if (!server->lock) {
		return;
	}
	struct wlr_session_lock_surface_v1 *ls;
	wl_list_for_each(ls, &server->lock->surfaces, link) {
		struct ul_lock_surface *l = ls->data;
		struct wlr_box out;
		wlr_output_layout_get_box(server->output_layout, ls->output, &out);
		if (l) {
			wlr_scene_node_set_position(&l->tree->node, out.x, out.y);
		}
		wlr_session_lock_surface_v1_configure(ls, out.width, out.height);
	}
}

static void lock_surface_map(struct wl_listener *listener, void *data) {
	struct ul_lock_surface *l = wl_container_of(listener, l, map);
	struct ul_server *server = l->server;
	/* Give the keyboard to the lock surface on the output under the pointer,
	 * or to the first one that shows up. */
	struct wlr_output *under = wlr_output_layout_output_at(server->output_layout,
		server->cursor->x, server->cursor->y);
	if (!server->seat->keyboard_state.focused_surface ||
			!wlr_session_lock_surface_v1_try_from_wlr_surface(
				server->seat->keyboard_state.focused_surface) ||
			l->lock_surface->output == under) {
		focus_lock_surface(server, l->lock_surface->surface);
	}
	input_update_pointer_focus(server, 0);
}

static void lock_surface_destroy(struct wl_listener *listener, void *data) {
	struct ul_lock_surface *l = wl_container_of(listener, l, destroy);
	wl_list_remove(&l->map.link);
	wl_list_remove(&l->destroy.link);
	l->lock_surface->data = NULL;
	free(l);
}

static void new_lock_surface(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, lock_new_surface);
	struct wlr_session_lock_surface_v1 *ls = data;
	struct ul_lock_surface *l = calloc(1, sizeof(*l));
	l->server = server;
	l->lock_surface = ls;
	l->tree = wlr_scene_subsurface_tree_create(server->layers[UL_LAYER_LOCK], ls->surface);
	ls->data = l;
	l->map.notify = lock_surface_map;
	wl_signal_add(&ls->surface->events.map, &l->map);
	l->destroy.notify = lock_surface_destroy;
	wl_signal_add(&ls->events.destroy, &l->destroy);
	lock_arrange(server);
}

static void detach_lock(struct ul_server *server) {
	wl_list_remove(&server->lock_new_surface.link);
	wl_list_remove(&server->lock_unlock.link);
	wl_list_remove(&server->lock_destroy.link);
	server->lock = NULL;
}

static void lock_unlock(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, lock_unlock);
	detach_lock(server);
	server->locked = false;
	wlr_scene_node_set_enabled(&server->lock_cover->node, false);
	wlr_seat_keyboard_notify_clear_focus(server->seat);
	if (server->focused_view) {
		struct ul_view *view = server->focused_view;
		server->focused_view = NULL;
		view_focus(view);
	}
	input_update_pointer_focus(server, 0);
	wlr_log(WLR_INFO, "Session unlocked");
}

static void lock_destroy(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, lock_destroy);
	/* Destroyed without unlocking (lock client crashed or was killed): stay
	 * locked behind the cover. A new lock client can take over. */
	detach_lock(server);
	if (server->locked) {
		wlr_log(WLR_ERROR, "Lock client went away while locked; staying locked");
	}
}

static void new_lock(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, new_lock);
	struct wlr_session_lock_v1 *lock = data;
	if (server->lock) {
		/* Only one lock client at a time. */
		wlr_session_lock_v1_destroy(lock);
		return;
	}
	server->lock = lock;
	server->locked = true;
	wlr_scene_node_set_enabled(&server->lock_cover->node, true);
	wlr_seat_keyboard_notify_clear_focus(server->seat);
	wlr_seat_pointer_clear_focus(server->seat);

	server->lock_new_surface.notify = new_lock_surface;
	wl_signal_add(&lock->events.new_surface, &server->lock_new_surface);
	server->lock_unlock.notify = lock_unlock;
	wl_signal_add(&lock->events.unlock, &server->lock_unlock);
	server->lock_destroy.notify = lock_destroy;
	wl_signal_add(&lock->events.destroy, &server->lock_destroy);

	lock_arrange(server);
	/* The cover already hides every other surface, so it's safe to confirm. */
	wlr_session_lock_v1_send_locked(lock);
	wlr_log(WLR_INFO, "Session locked");
}

/* ---- idle ---------------------------------------------------------------- */

void idle_activity(struct ul_server *server) {
	wlr_idle_notifier_v1_notify_activity(server->idle_notifier, server->seat);
}

/* Idle (dim, lock, suspend) is held off while an app asks for it (video,
 * games via SDL/Wine) or while any window is fullscreen. */
void idle_update_inhibit(struct ul_server *server) {
	bool fullscreen = false;
	struct ul_view *view;
	wl_list_for_each(view, &server->views, link) {
		if (view->mapped && view->fullscreen && !view->minimized) {
			fullscreen = true;
			break;
		}
	}
	wlr_idle_notifier_v1_set_inhibited(server->idle_notifier,
		server->idle_inhibitors > 0 || fullscreen);
}

struct ul_inhibitor {
	struct ul_server *server;
	struct wl_listener destroy;
};

static void inhibitor_destroy(struct wl_listener *listener, void *data) {
	struct ul_inhibitor *i = wl_container_of(listener, i, destroy);
	struct ul_server *server = i->server;
	server->idle_inhibitors--;
	wl_list_remove(&i->destroy.link);
	free(i);
	idle_update_inhibit(server);
}

static void new_inhibitor(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, new_inhibitor);
	struct wlr_idle_inhibitor_v1 *inhibitor = data;
	struct ul_inhibitor *i = calloc(1, sizeof(*i));
	i->server = server;
	i->destroy.notify = inhibitor_destroy;
	wl_signal_add(&inhibitor->events.destroy, &i->destroy);
	server->idle_inhibitors++;
	idle_update_inhibit(server);
}

void lock_init(struct ul_server *server) {
	static const float cover[4] = UL_COLOR_BG;
	server->lock_cover = wlr_scene_rect_create(server->layers[UL_LAYER_LOCK], 0, 0, cover);
	/* Restarted after a crash (ultimit-run-compositor): start covered and locked, as if the lock
	 * client had gone away, so a crash can't skip the lock screen. The shell locks on start. */
	const char *start_locked = getenv("ULTIMIT_START_LOCKED");
	server->locked = start_locked && strcmp(start_locked, "1") == 0;
	wlr_scene_node_set_enabled(&server->lock_cover->node, server->locked);
	if (server->locked) {
		wlr_log(WLR_INFO, "Starting locked (restarted after a crash)");
	}

	server->lock_manager = wlr_session_lock_manager_v1_create(server->display);
	server->new_lock.notify = new_lock;
	wl_signal_add(&server->lock_manager->events.new_lock, &server->new_lock);

	server->idle_notifier = wlr_idle_notifier_v1_create(server->display);
	struct wlr_idle_inhibit_manager_v1 *inhibit = wlr_idle_inhibit_v1_create(server->display);
	server->new_inhibitor.notify = new_inhibitor;
	wl_signal_add(&inhibit->events.new_inhibitor, &server->new_inhibitor);
}

void lock_finish(struct ul_server *server) {
	if (server->lock) {
		detach_lock(server);
	}
	wl_list_remove(&server->new_lock.link);
	wl_list_remove(&server->new_inhibitor.link);
}
