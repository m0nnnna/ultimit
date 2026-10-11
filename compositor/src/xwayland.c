/*
 * xwayland.c: X11 clients. Steam and most Proton/Wine games still run here,
 * so this path has to be as solid as the native one. Managed windows become
 * views; override-redirect windows (menus, tooltips, Steam's popups) are
 * drawn as-is above everything at the position X asked for.
 */

#include <stdlib.h>
#include "server.h"
#include "theme.h"

struct ul_unmanaged {
	struct ul_server *server;
	struct wlr_xwayland_surface *xsurface;
	struct wlr_scene_tree *tree;
	struct wl_listener associate;
	struct wl_listener dissociate;
	struct wl_listener map;
	struct wl_listener unmap;
	struct wl_listener request_configure;
	struct wl_listener set_geometry;
	struct wl_listener destroy;
};

/* ---- override-redirect --------------------------------------------------- */

static void unmanaged_map(struct wl_listener *listener, void *data) {
	struct ul_unmanaged *u = wl_container_of(listener, u, map);
	u->tree = wlr_scene_subsurface_tree_create(u->server->layers[UL_LAYER_OVERLAY],
		u->xsurface->surface);
	wlr_scene_node_set_position(&u->tree->node, u->xsurface->x, u->xsurface->y);
	if (wlr_xwayland_surface_override_redirect_wants_focus(u->xsurface)) {
		struct wlr_keyboard *keyboard = wlr_seat_get_keyboard(u->server->seat);
		wlr_seat_keyboard_notify_enter(u->server->seat, u->xsurface->surface,
			keyboard ? keyboard->keycodes : NULL, keyboard ? keyboard->num_keycodes : 0,
			keyboard ? &keyboard->modifiers : NULL);
	}
}

static void unmanaged_unmap(struct wl_listener *listener, void *data) {
	struct ul_unmanaged *u = wl_container_of(listener, u, unmap);
	if (u->tree) {
		wlr_scene_node_destroy(&u->tree->node);
		u->tree = NULL;
	}
	struct ul_server *server = u->server;
	if (server->seat->keyboard_state.focused_surface == u->xsurface->surface) {
		if (server->focused_view) {
			struct ul_view *view = server->focused_view;
			server->focused_view = NULL;
			view_focus(view);
		} else {
			wlr_seat_keyboard_notify_clear_focus(server->seat);
		}
	}
}

static void unmanaged_set_geometry(struct wl_listener *listener, void *data) {
	struct ul_unmanaged *u = wl_container_of(listener, u, set_geometry);
	if (u->tree) {
		wlr_scene_node_set_position(&u->tree->node, u->xsurface->x, u->xsurface->y);
	}
}

static void unmanaged_request_configure(struct wl_listener *listener, void *data) {
	struct ul_unmanaged *u = wl_container_of(listener, u, request_configure);
	struct wlr_xwayland_surface_configure_event *event = data;
	wlr_xwayland_surface_configure(u->xsurface, event->x, event->y,
		event->width, event->height);
}

/* wlroots maps an X11 surface on its first commit *after* the X window and
 * the wl_surface are paired. Xwayland can commit the window's only frame
 * before the pairing message arrives; a window that never redraws (dialogs,
 * launchers, a game's splash) would then never appear. Map it here instead. */
static void map_if_ready(struct wlr_surface *surface) {
	if (!surface->mapped && wlr_surface_has_buffer(surface)) {
		wlr_surface_map(surface);
	}
}

static void unmanaged_associate(struct wl_listener *listener, void *data) {
	struct ul_unmanaged *u = wl_container_of(listener, u, associate);
	u->map.notify = unmanaged_map;
	wl_signal_add(&u->xsurface->surface->events.map, &u->map);
	u->unmap.notify = unmanaged_unmap;
	wl_signal_add(&u->xsurface->surface->events.unmap, &u->unmap);
	map_if_ready(u->xsurface->surface);
}

static void unmanaged_dissociate(struct wl_listener *listener, void *data) {
	struct ul_unmanaged *u = wl_container_of(listener, u, dissociate);
	wl_list_remove(&u->map.link);
	wl_list_remove(&u->unmap.link);
}

static void unmanaged_destroy(struct wl_listener *listener, void *data) {
	struct ul_unmanaged *u = wl_container_of(listener, u, destroy);
	wl_list_remove(&u->associate.link);
	wl_list_remove(&u->dissociate.link);
	wl_list_remove(&u->request_configure.link);
	wl_list_remove(&u->set_geometry.link);
	wl_list_remove(&u->destroy.link);
	free(u);
}

static void create_unmanaged(struct ul_server *server, struct wlr_xwayland_surface *xsurface) {
	struct ul_unmanaged *u = calloc(1, sizeof(*u));
	u->server = server;
	u->xsurface = xsurface;
	u->associate.notify = unmanaged_associate;
	wl_signal_add(&xsurface->events.associate, &u->associate);
	u->dissociate.notify = unmanaged_dissociate;
	wl_signal_add(&xsurface->events.dissociate, &u->dissociate);
	u->request_configure.notify = unmanaged_request_configure;
	wl_signal_add(&xsurface->events.request_configure, &u->request_configure);
	u->set_geometry.notify = unmanaged_set_geometry;
	wl_signal_add(&xsurface->events.set_geometry, &u->set_geometry);
	u->destroy.notify = unmanaged_destroy;
	wl_signal_add(&xsurface->events.destroy, &u->destroy);
}

/* ---- managed windows ----------------------------------------------------- */

static bool wants_ssd(struct wlr_xwayland_surface *xsurface) {
	/* Motif hints: a client that turns decorations off draws its own (or is a
	 * borderless game window). */
	return xsurface->decorations == WLR_XWAYLAND_SURFACE_DECORATIONS_ALL;
}

static void x_map(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, map);
	struct wlr_xwayland_surface *xsurface = view->xwayland_surface;
	view->content = wlr_scene_subsurface_tree_create(view->tree, xsurface->surface);
	view->width = xsurface->width;
	view->height = xsurface->height;
	view->ssd = wants_ssd(xsurface);
	view_map(view);
	if (xsurface->fullscreen) {
		view_set_fullscreen(view, true);
	} else if (xsurface->maximized_horz && xsurface->maximized_vert) {
		view_set_maximized(view, true);
	}
}

static void x_unmap(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, unmap);
	view_unmap(view);
	if (view->content) {
		wlr_scene_node_destroy(&view->content->node);
		view->content = NULL;
	}
}

static void x_commit(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, commit);
	struct wlr_surface *surface = view->xwayland_surface->surface;
	if (view->mapped) {
		view_update_size(view, surface->current.width, surface->current.height);
	}
}

static void x_associate(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, associate);
	struct wlr_surface *surface = view->xwayland_surface->surface;
	view->map.notify = x_map;
	wl_signal_add(&surface->events.map, &view->map);
	view->unmap.notify = x_unmap;
	wl_signal_add(&surface->events.unmap, &view->unmap);
	view->commit.notify = x_commit;
	wl_signal_add(&surface->events.commit, &view->commit);
	map_if_ready(surface);
}

static void x_dissociate(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, dissociate);
	wl_list_remove(&view->map.link);
	wl_list_remove(&view->unmap.link);
	wl_list_remove(&view->commit.link);
}

static void x_request_configure(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, request_configure);
	struct wlr_xwayland_surface_configure_event *event = data;
	if (!view->mapped) {
		view->x = event->x;
		view->y = event->y;
		wlr_xwayland_surface_configure(view->xwayland_surface,
			event->x, event->y, event->width, event->height);
		return;
	}
	if (view->fullscreen || view->maximized || view->snapped) {
		/* Tell the client the size it already has. */
		wlr_xwayland_surface_configure(view->xwayland_surface,
			view->x, view->y, view->width, view->height);
		return;
	}
	/* X11 apps place themselves; keep them clear of the rail and the
	 * bottom bar. A window that covers a whole output is a game asking for
	 * borderless fullscreen (Wine does this): make it real fullscreen. */
	struct ul_output *output = output_at(view->server,
		event->x + event->width / 2.0, event->y + event->height / 2.0);
	if (output) {
		struct wlr_box full = output->full_area, area = output->usable_area;
		if (event->x <= full.x && event->y <= full.y &&
				event->width >= full.width && event->height >= full.height) {
			view_set_fullscreen(view, true);
			return;
		}
		int bar = view->ssd ? UL_TITLEBAR_H : 0;
		int x = event->x, y = event->y;
		if (x + event->width > area.x + area.width) x = area.x + area.width - event->width;
		if (y + event->height > area.y + area.height) y = area.y + area.height - event->height;
		if (x < area.x) x = area.x;
		if (y < area.y + bar) y = area.y + bar;
		view->x = x;
		view->y = y;
		view_request_size(view, event->width, event->height);
		view_set_position(view, x, y);
		return;
	}
	view->x = event->x;
	view->y = event->y;
	view_request_size(view, event->width, event->height);
	view_set_position(view, event->x, event->y);
}

static void x_request_activate(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, request_activate);
	view_focus(view);
}

static void x_request_move(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, request_move);
	view_begin_interactive(view, UL_CURSOR_MOVE, 0);
}

static void x_request_resize(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, request_resize);
	struct wlr_xwayland_resize_event *event = data;
	view_begin_interactive(view, UL_CURSOR_RESIZE, event->edges);
}

static void x_request_maximize(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, request_maximize);
	struct wlr_xwayland_surface *xs = view->xwayland_surface;
	if (view->mapped) {
		view_set_maximized(view, xs->maximized_horz && xs->maximized_vert);
	}
}

static void x_request_fullscreen(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, request_fullscreen);
	if (view->mapped) {
		view_set_fullscreen(view, view->xwayland_surface->fullscreen);
	}
}

static void x_request_minimize(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, request_minimize);
	struct wlr_xwayland_minimize_event *event = data;
	if (view->mapped) {
		if (event->minimize) {
			view_set_minimized(view, true);
		} else {
			view_focus(view);
		}
	}
}

static void x_set_title(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, set_title);
	view_update_title(view);
}

static void x_set_class(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, set_app_id);
	view_update_title(view);
}

static void x_set_decorations(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, set_decorations);
	view_set_ssd(view, wants_ssd(view->xwayland_surface));
}

static void x_destroy(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, destroy);
	wl_list_remove(&view->associate.link);
	wl_list_remove(&view->dissociate.link);
	wl_list_remove(&view->destroy.link);
	wl_list_remove(&view->request_configure.link);
	wl_list_remove(&view->request_activate.link);
	wl_list_remove(&view->request_move.link);
	wl_list_remove(&view->request_resize.link);
	wl_list_remove(&view->request_maximize.link);
	wl_list_remove(&view->request_fullscreen.link);
	wl_list_remove(&view->request_minimize.link);
	wl_list_remove(&view->set_title.link);
	wl_list_remove(&view->set_app_id.link);
	wl_list_remove(&view->set_decorations.link);
	view_destroy(view);
}

static void create_view(struct ul_server *server, struct wlr_xwayland_surface *xsurface) {
	struct ul_view *view = calloc(1, sizeof(*view));
	view->server = server;
	view->type = UL_VIEW_XWAYLAND;
	view->id = ++server->next_view_id;
	view->xwayland_surface = xsurface;
	wl_list_init(&view->link);

	view->tree = wlr_scene_tree_create(server->layers[UL_LAYER_VIEWS]);
	view->tree->node.data = view;
	wlr_scene_node_set_enabled(&view->tree->node, false);
	decoration_create(view);

	view->associate.notify = x_associate;
	wl_signal_add(&xsurface->events.associate, &view->associate);
	view->dissociate.notify = x_dissociate;
	wl_signal_add(&xsurface->events.dissociate, &view->dissociate);
	view->destroy.notify = x_destroy;
	wl_signal_add(&xsurface->events.destroy, &view->destroy);
	view->request_configure.notify = x_request_configure;
	wl_signal_add(&xsurface->events.request_configure, &view->request_configure);
	view->request_activate.notify = x_request_activate;
	wl_signal_add(&xsurface->events.request_activate, &view->request_activate);
	view->request_move.notify = x_request_move;
	wl_signal_add(&xsurface->events.request_move, &view->request_move);
	view->request_resize.notify = x_request_resize;
	wl_signal_add(&xsurface->events.request_resize, &view->request_resize);
	view->request_maximize.notify = x_request_maximize;
	wl_signal_add(&xsurface->events.request_maximize, &view->request_maximize);
	view->request_fullscreen.notify = x_request_fullscreen;
	wl_signal_add(&xsurface->events.request_fullscreen, &view->request_fullscreen);
	view->request_minimize.notify = x_request_minimize;
	wl_signal_add(&xsurface->events.request_minimize, &view->request_minimize);
	view->set_title.notify = x_set_title;
	wl_signal_add(&xsurface->events.set_title, &view->set_title);
	view->set_app_id.notify = x_set_class;
	wl_signal_add(&xsurface->events.set_class, &view->set_app_id);
	view->set_decorations.notify = x_set_decorations;
	wl_signal_add(&xsurface->events.set_decorations, &view->set_decorations);
}

static void new_surface(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, new_xwayland_surface);
	struct wlr_xwayland_surface *xsurface = data;
	if (xsurface->override_redirect) {
		create_unmanaged(server, xsurface);
	} else {
		create_view(server, xsurface);
	}
}

static void ready(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, xwayland_ready);
	wlr_xwayland_set_seat(server->xwayland, server->seat);
	wlr_log(WLR_INFO, "XWayland ready on DISPLAY=%s", server->xwayland->display_name);
}

void xwayland_init(struct ul_server *server) {
	/* Not lazy: a lazy XWayland exits with its last client and takes seconds
	 * to come back, and an X11 app (Steam, a game) started in that gap fails
	 * to connect. Keeping it up costs ~30 MB. */
	server->xwayland = wlr_xwayland_create(server->display, server->compositor, false);
	if (!server->xwayland) {
		wlr_log(WLR_ERROR, "XWayland unavailable; X11 apps and Steam will not run");
		return;
	}
	server->xwayland_ready.notify = ready;
	wl_signal_add(&server->xwayland->events.ready, &server->xwayland_ready);
	server->new_xwayland_surface.notify = new_surface;
	wl_signal_add(&server->xwayland->events.new_surface, &server->new_xwayland_surface);
	setenv("DISPLAY", server->xwayland->display_name, true);
}
