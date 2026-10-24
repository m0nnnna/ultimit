/*
 * lock.c: screen locking (ext-session-lock-v1) and idle (ext-idle-notify-v1,
 * idle-inhibit-v1).
 *
 * The lock screen itself is a Quickshell client. The compositor's job is to
 * make the lock trustworthy: while locked, a solid cover hides everything,
 * only lock surfaces get input, and if the lock client crashes the session
 * stays covered and locked until a new lock client unlocks it.
 */

#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
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

/* Is this client the shell (the `qs` found on PATH, which is how
 * ultimit-shell starts it)? Unknown when qs can't be found: then yes, so a
 * dev setup without it on PATH keeps working. */
static bool client_is_shell(struct wl_client *client) {
	static char shell_exe[PATH_MAX];
	static bool looked;
	if (!looked) {
		looked = true;
		const char *path = getenv("PATH");
		char *dirs = strdup(path ? path : "");
		for (char *save = NULL, *dir = strtok_r(dirs, ":", &save); dir;
				dir = strtok_r(NULL, ":", &save)) {
			char cand[PATH_MAX];
			snprintf(cand, sizeof(cand), "%s/qs", dir);
			if (access(cand, X_OK) == 0 && realpath(cand, shell_exe)) {
				break;
			}
			shell_exe[0] = '\0';
		}
		free(dirs);
	}
	if (!shell_exe[0]) {
		return true;
	}
	pid_t pid;
	wl_client_get_credentials(client, &pid, NULL, NULL);
	char link[64], exe[PATH_MAX];
	snprintf(link, sizeof(link), "/proc/%d/exe", pid);
	ssize_t n = readlink(link, exe, sizeof(exe) - 1);
	if (n <= 0) {
		return false;
	}
	exe[n] = '\0';
	return strcmp(exe, shell_exe) == 0;
}

static void new_lock(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, new_lock);
	struct wlr_session_lock_v1 *lock = data;
	if (server->lock) {
		/* Only one lock client at a time. */
		wlr_session_lock_v1_destroy(lock);
		return;
	}
	if (server->locked && !client_is_shell(wl_resource_get_client(lock->resource))) {
		/* The lock client died while locked: only the restarted shell may take
		 * over. Anyone else could lock and at once unlock, skipping the password. */
		wlr_log(WLR_ERROR, "Refused a lock takeover from a client that is not the shell");
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

struct ul_inhibitor {
	struct wl_list link; /* inhibitors */
	struct ul_server *server;
	struct wlr_idle_inhibitor_v1 *inhibitor;
	struct wl_listener destroy;
};

static struct wl_list inhibitors = {&inhibitors, &inhibitors};

/* An inhibitor counts only while its surface can be seen: mapped, and its
 * window (if it is one) not minimized. Otherwise a hidden window could keep
 * the screen from ever locking. */
static bool inhibitor_visible(struct ul_server *server, struct wlr_surface *surface) {
	struct wlr_surface *root = wlr_surface_get_root_surface(surface);
	if (!root || !root->mapped) {
		return false;
	}
	struct ul_view *view;
	wl_list_for_each(view, &server->views, link) {
		if (view_surface(view) == root) {
			return view->mapped && !view->minimized;
		}
	}
	return true; /* a panel or an X11 override window: mapped is enough */
}

/* Idle (dim, lock, suspend) is held off while a visible app asks for it
 * (video, games via SDL/Wine) or while the focused window is fullscreen.
 * Only the focused one: an unfocused (or invisible) fullscreen window
 * must not stop the auto-lock. */
void idle_update_inhibit(struct ul_server *server) {
	struct ul_view *focused = server->focused_view;
	bool fullscreen = focused && focused->mapped && focused->fullscreen && !focused->minimized;
	int active = 0;
	struct ul_inhibitor *i;
	wl_list_for_each(i, &inhibitors, link) {
		if (inhibitor_visible(server, i->inhibitor->surface)) {
			active++;
		}
	}
	server->idle_inhibitors = active;
	wlr_idle_notifier_v1_set_inhibited(server->idle_notifier, active > 0 || fullscreen);
}

static void inhibitor_destroy(struct wl_listener *listener, void *data) {
	struct ul_inhibitor *i = wl_container_of(listener, i, destroy);
	struct ul_server *server = i->server;
	wl_list_remove(&i->link);
	wl_list_remove(&i->destroy.link);
	free(i);
	idle_update_inhibit(server);
}

static void new_inhibitor(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, new_inhibitor);
	struct wlr_idle_inhibitor_v1 *inhibitor = data;
	struct ul_inhibitor *i = calloc(1, sizeof(*i));
	i->server = server;
	i->inhibitor = inhibitor;
	i->destroy.notify = inhibitor_destroy;
	wl_signal_add(&inhibitor->events.destroy, &i->destroy);
	wl_list_insert(&inhibitors, &i->link);
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
