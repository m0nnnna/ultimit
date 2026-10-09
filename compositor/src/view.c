/*
 * view.c: everything a window does regardless of whether it's a native
 * Wayland (xdg-shell) client or an X11 client through XWayland: focus,
 * stacking, placement, maximize/fullscreen/minimize, interactive move and
 * resize, and the foreign-toplevel handle the shell's rail uses.
 */

#include <stdlib.h>
#include <xcb/xproto.h>
#include "server.h"
#include "theme.h"

struct ul_view *view_from_node(struct wlr_scene_node *node) {
	while (node) {
		if (node->data) {
			return node->data;
		}
		node = node->parent ? &node->parent->node : NULL;
	}
	return NULL;
}

struct wlr_surface *view_surface(struct ul_view *view) {
	if (view->type == UL_VIEW_XDG) {
		return view->xdg_toplevel->base->surface;
	}
	return view->xwayland_surface->surface;
}

struct wlr_box view_geometry_offset(struct ul_view *view) {
	if (view->type == UL_VIEW_XDG) {
		return view->xdg_toplevel->base->geometry;
	}
	return (struct wlr_box){ 0, 0, view->width, view->height };
}

const char *view_title(struct ul_view *view) {
	const char *title = view->type == UL_VIEW_XDG ?
		view->xdg_toplevel->title : view->xwayland_surface->title;
	return title ? title : "";
}

const char *view_app_id(struct ul_view *view) {
	const char *id = view->type == UL_VIEW_XDG ?
		view->xdg_toplevel->app_id : view->xwayland_surface->class;
	return id ? id : "";
}

static void view_set_activated(struct ul_view *view, bool activated) {
	if (view->type == UL_VIEW_XDG) {
		wlr_xdg_toplevel_set_activated(view->xdg_toplevel, activated);
	} else {
		wlr_xwayland_surface_activate(view->xwayland_surface, activated);
		if (activated) {
			wlr_xwayland_surface_restack(view->xwayland_surface, NULL, XCB_STACK_MODE_ABOVE);
		}
	}
	if (view->foreign) {
		wlr_foreign_toplevel_handle_v1_set_activated(view->foreign, activated);
	}
}

void view_focus(struct ul_view *view) {
	if (!view || !view->mapped) {
		return;
	}
	struct ul_server *server = view->server;
	if (view->minimized) {
		view_set_minimized(view, false);
	}

	struct ul_view *prev = server->focused_view;
	wlr_scene_node_raise_to_top(&view->tree->node);
	wl_list_remove(&view->link);
	wl_list_insert(&server->views, &view->link);

	if (prev != view) {
		if (prev) {
			view_set_activated(prev, false);
			decoration_update(prev);
		}
		server->focused_view = view;
		view_set_activated(view, true);
		decoration_update(view);
	}

	/* A layer surface with exclusive keyboard focus (lock screen, launcher)
	 * keeps the keyboard until it lets go. */
	if (server->focused_layer &&
			server->focused_layer->current.keyboard_interactive ==
			ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE) {
		return;
	}
	server->focused_layer = NULL;
	struct wlr_keyboard *keyboard = wlr_seat_get_keyboard(server->seat);
	struct wlr_surface *surface = view_surface(view);
	if (keyboard && surface) {
		wlr_seat_keyboard_notify_enter(server->seat, surface,
			keyboard->keycodes, keyboard->num_keycodes, &keyboard->modifiers);
	} else if (surface) {
		wlr_seat_keyboard_notify_enter(server->seat, surface, NULL, 0, NULL);
	}
}

void view_focus_next(struct ul_server *server) {
	/* Cycle: bring the least recently focused window to the front. */
	struct ul_view *view;
	wl_list_for_each_reverse(view, &server->views, link) {
		if (view->mapped && view != server->focused_view) {
			view_focus(view);
			return;
		}
	}
}

static void focus_topmost(struct ul_server *server) {
	struct ul_view *view;
	wl_list_for_each(view, &server->views, link) {
		if (view->mapped && !view->minimized) {
			view_focus(view);
			return;
		}
	}
	server->focused_view = NULL;
	wlr_seat_keyboard_notify_clear_focus(server->seat);
}

void view_set_position(struct ul_view *view, int x, int y) {
	view->x = x;
	view->y = y;
	struct wlr_box geo = view_geometry_offset(view);
	wlr_scene_node_set_position(&view->tree->node, x - geo.x, y - geo.y);
	if (view->type == UL_VIEW_XWAYLAND) {
		wlr_xwayland_surface_configure(view->xwayland_surface,
			x, y, view->width, view->height);
	}
}

void view_request_size(struct ul_view *view, int width, int height) {
	if (width < 1) width = 1;
	if (height < 1) height = 1;
	if (view->type == UL_VIEW_XDG) {
		wlr_xdg_toplevel_set_size(view->xdg_toplevel, width, height);
	} else {
		view->width = width;
		view->height = height;
		wlr_xwayland_surface_configure(view->xwayland_surface,
			view->x, view->y, width, height);
		decoration_update(view);
	}
}

/* Called when the client commits a new size. */
void view_update_size(struct ul_view *view, int width, int height) {
	if (width == view->width && height == view->height) {
		/* Geometry offset may still have moved. */
		view_set_position(view, view->x, view->y);
		return;
	}
	struct ul_server *server = view->server;
	/* Keep the right/bottom edge anchored while resizing from the left/top. */
	if (server->cursor_mode == UL_CURSOR_RESIZE && server->grabbed_view == view) {
		if (server->resize_edges & WLR_EDGE_LEFT) {
			view->x += view->width - width;
		}
		if (server->resize_edges & WLR_EDGE_TOP) {
			view->y += view->height - height;
		}
	}
	view->width = width;
	view->height = height;
	view_set_position(view, view->x, view->y);
	decoration_update(view);
}

static struct wlr_box output_box(struct ul_view *view, bool usable) {
	struct ul_output *output = output_for_view(view);
	if (!output) {
		return (struct wlr_box){ 0, 0, 1280, 720 };
	}
	return usable ? output->usable_area : output->full_area;
}

void view_set_maximized(struct ul_view *view, bool maximized) {
	if (view->fullscreen || view->maximized == maximized) {
		goto done;
	}
	if (maximized) {
		view->saved = (struct wlr_box){ view->x, view->y, view->width, view->height };
		struct wlr_box area = output_box(view, true);
		int bar = view->ssd ? UL_TITLEBAR_H : 0;
		view->maximized = true;
		view_set_position(view, area.x + UL_BORDER, area.y + bar + UL_BORDER);
		view_request_size(view, area.width - 2 * UL_BORDER, area.height - bar - 2 * UL_BORDER);
	} else {
		view->maximized = false;
		view_set_position(view, view->saved.x, view->saved.y);
		view_request_size(view, view->saved.width, view->saved.height);
	}
	if (view->type == UL_VIEW_XDG) {
		wlr_xdg_toplevel_set_maximized(view->xdg_toplevel, maximized);
	} else {
		wlr_xwayland_surface_set_maximized(view->xwayland_surface, maximized, maximized);
	}
	if (view->foreign) {
		wlr_foreign_toplevel_handle_v1_set_maximized(view->foreign, maximized);
	}
done:
	if (view->type == UL_VIEW_XDG && view->xdg_toplevel->base->initialized) {
		wlr_xdg_surface_schedule_configure(view->xdg_toplevel->base);
	}
}

static void set_backdrop_blur(struct wlr_scene_buffer *buffer, int sx, int sy, void *data) {
	bool *enabled = data;
	if (wlr_scene_surface_try_from_buffer(buffer)) {
		wlr_scene_buffer_set_backdrop_blur(buffer, *enabled);
		wlr_scene_buffer_set_backdrop_blur_optimized(buffer, *enabled);
	}
}

void view_set_fullscreen(struct ul_view *view, bool fullscreen) {
	struct ul_server *server = view->server;
	if (view->fullscreen == fullscreen) {
		goto done;
	}
	if (fullscreen) {
		if (!view->maximized) {
			view->saved = (struct wlr_box){ view->x, view->y, view->width, view->height };
		}
		struct wlr_box area = output_box(view, false);
		view->fullscreen = true;
		/* Above panels, and nothing drawn over it, so a game's buffer can be
		 * scanned out directly. */
		wlr_scene_node_reparent(&view->tree->node, server->layers[UL_LAYER_FULLSCREEN]);
		view_set_position(view, area.x, area.y);
		view_request_size(view, area.width, area.height);
	} else {
		view->fullscreen = false;
		wlr_scene_node_reparent(&view->tree->node, server->layers[UL_LAYER_VIEWS]);
		if (view->maximized) {
			view->maximized = false;
			view_set_maximized(view, true);
		} else {
			view_set_position(view, view->saved.x, view->saved.y);
			view_request_size(view, view->saved.width, view->saved.height);
		}
	}
	bool blur = !fullscreen;
	wlr_scene_node_for_each_buffer(&view->content->node, set_backdrop_blur, &blur);
	if (view->type == UL_VIEW_XDG) {
		wlr_xdg_toplevel_set_fullscreen(view->xdg_toplevel, fullscreen);
	} else {
		wlr_xwayland_surface_set_fullscreen(view->xwayland_surface, fullscreen);
	}
	if (view->foreign) {
		wlr_foreign_toplevel_handle_v1_set_fullscreen(view->foreign, fullscreen);
	}
	decoration_update(view);
done:
	if (view->type == UL_VIEW_XDG && view->xdg_toplevel->base->initialized) {
		wlr_xdg_surface_schedule_configure(view->xdg_toplevel->base);
	}
}

void view_set_minimized(struct ul_view *view, bool minimized) {
	if (view->minimized == minimized) {
		return;
	}
	view->minimized = minimized;
	wlr_scene_node_set_enabled(&view->tree->node, !minimized);
	if (view->type == UL_VIEW_XWAYLAND) {
		wlr_xwayland_surface_set_minimized(view->xwayland_surface, minimized);
	}
	if (view->foreign) {
		wlr_foreign_toplevel_handle_v1_set_minimized(view->foreign, minimized);
	}
	if (minimized && view->server->focused_view == view) {
		view_set_activated(view, false);
		view->server->focused_view = NULL;
		focus_topmost(view->server);
	}
}

void view_close(struct ul_view *view) {
	if (view->type == UL_VIEW_XDG) {
		wlr_xdg_toplevel_send_close(view->xdg_toplevel);
	} else {
		wlr_xwayland_surface_close(view->xwayland_surface);
	}
}

void view_begin_interactive(struct ul_view *view, enum ul_cursor_mode mode, uint32_t edges) {
	struct ul_server *server = view->server;
	if (view->fullscreen) {
		return;
	}
	if (mode == UL_CURSOR_MOVE && view->maximized) {
		/* Dragging a maximized window restores it under the pointer, keeping
		 * the same relative grab point. */
		double rel = (server->cursor->x - view->x) / (double)(view->width ? view->width : 1);
		view_set_maximized(view, false);
		int x = server->cursor->x - rel * view->saved.width;
		view_set_position(view, x, view->y);
	}
	server->grabbed_view = view;
	server->cursor_mode = mode;
	if (mode == UL_CURSOR_MOVE) {
		server->grab_x = server->cursor->x - view->x;
		server->grab_y = server->cursor->y - view->y;
	} else {
		double bx = view->x + ((edges & WLR_EDGE_RIGHT) ? view->width : 0);
		double by = view->y + ((edges & WLR_EDGE_BOTTOM) ? view->height : 0);
		server->grab_x = server->cursor->x - bx;
		server->grab_y = server->cursor->y - by;
		server->grab_box = (struct wlr_box){ view->x, view->y, view->width, view->height };
		server->resize_edges = edges;
		if (view->type == UL_VIEW_XDG) {
			wlr_xdg_toplevel_set_resizing(view->xdg_toplevel, true);
		}
	}
}

void view_update_title(struct ul_view *view) {
	if (view->foreign) {
		wlr_foreign_toplevel_handle_v1_set_title(view->foreign, view_title(view));
		wlr_foreign_toplevel_handle_v1_set_app_id(view->foreign, view_app_id(view));
	}
	if (view->mapped && view->ssd) {
		decoration_update(view);
	}
}

void view_set_ssd(struct ul_view *view, bool ssd) {
	if (view->ssd == ssd) {
		return;
	}
	view->ssd = ssd;
	if (view->mapped) {
		/* Keep the content where it is; the titlebar grows upward. */
		decoration_update(view);
	}
}

bool view_wants_tearing(struct ul_view *view) {
	struct wlr_surface *surface = view_surface(view);
	if (!surface) {
		return false;
	}
	return wlr_tearing_control_manager_v1_surface_hint_from_surface(
		view->server->tearing_control, surface) ==
		WP_TEARING_CONTROL_V1_PRESENTATION_HINT_ASYNC;
}

/* ---- foreign toplevel (the shell's rail / taskbar) ----------------------- */

static void foreign_activate(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, foreign_activate);
	view_focus(view);
}

static void foreign_close(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, foreign_close);
	view_close(view);
}

static void foreign_minimize(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, foreign_minimize);
	struct wlr_foreign_toplevel_handle_v1_minimized_event *event = data;
	if (event->minimized) {
		view_set_minimized(view, true);
	} else {
		view_focus(view);
	}
}

static void foreign_maximize(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, foreign_maximize);
	struct wlr_foreign_toplevel_handle_v1_maximized_event *event = data;
	view_set_maximized(view, event->maximized);
}

static void foreign_fullscreen(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, foreign_fullscreen);
	struct wlr_foreign_toplevel_handle_v1_fullscreen_event *event = data;
	view_set_fullscreen(view, event->fullscreen);
}

void view_init_foreign(struct ul_view *view) {
	view->foreign = wlr_foreign_toplevel_handle_v1_create(view->server->foreign_toplevels);
	view->foreign_activate.notify = foreign_activate;
	wl_signal_add(&view->foreign->events.request_activate, &view->foreign_activate);
	view->foreign_close.notify = foreign_close;
	wl_signal_add(&view->foreign->events.request_close, &view->foreign_close);
	view->foreign_minimize.notify = foreign_minimize;
	wl_signal_add(&view->foreign->events.request_minimize, &view->foreign_minimize);
	view->foreign_maximize.notify = foreign_maximize;
	wl_signal_add(&view->foreign->events.request_maximize, &view->foreign_maximize);
	view->foreign_fullscreen.notify = foreign_fullscreen;
	wl_signal_add(&view->foreign->events.request_fullscreen, &view->foreign_fullscreen);
	view_update_title(view);
}

static void finish_foreign(struct ul_view *view) {
	if (!view->foreign) {
		return;
	}
	wl_list_remove(&view->foreign_activate.link);
	wl_list_remove(&view->foreign_close.link);
	wl_list_remove(&view->foreign_minimize.link);
	wl_list_remove(&view->foreign_maximize.link);
	wl_list_remove(&view->foreign_fullscreen.link);
	wlr_foreign_toplevel_handle_v1_destroy(view->foreign);
	view->foreign = NULL;
}

/* ---- map / unmap --------------------------------------------------------- */

void view_map(struct ul_view *view) {
	struct ul_server *server = view->server;
	view->mapped = true;
	view->minimized = false;
	wlr_scene_node_set_enabled(&view->tree->node, true);
	view_init_foreign(view);

	/* Center new windows on the output under the pointer, inside the area
	 * the shell's panels leave free. */
	struct ul_output *output = output_at(server, server->cursor->x, server->cursor->y);
	if (output) {
		struct wlr_box area = output->usable_area;
		int bar = view->ssd ? UL_TITLEBAR_H : 0;
		int x = area.x + (area.width - view->width) / 2;
		int y = area.y + bar + (area.height - bar - view->height) / 2;
		if (x < area.x) x = area.x;
		if (y < area.y + bar) y = area.y + bar;
		view_set_position(view, x, y);
		wlr_foreign_toplevel_handle_v1_output_enter(view->foreign, output->wlr_output);
	} else {
		view_set_position(view, view->x, view->y);
	}

	wl_list_insert(&server->views, &view->link);
	decoration_update(view);
	view_focus(view);
}

void view_unmap(struct ul_view *view) {
	struct ul_server *server = view->server;
	view->mapped = false;
	wlr_scene_node_set_enabled(&view->tree->node, false);
	finish_foreign(view);
	if (server->grabbed_view == view) {
		server->cursor_mode = UL_CURSOR_PASSTHROUGH;
		server->grabbed_view = NULL;
	}
	if (server->last_click_view == view) {
		server->last_click_view = NULL;
	}
	wl_list_remove(&view->link);
	wl_list_init(&view->link);
	if (server->focused_view == view) {
		server->focused_view = NULL;
		focus_topmost(server);
	}
}

void view_destroy(struct ul_view *view) {
	finish_foreign(view);
	if (view->xdg_decoration) {
		wl_list_remove(&view->decoration_request_mode.link);
		wl_list_remove(&view->decoration_destroy.link);
	}
	wl_list_remove(&view->link);
	wlr_scene_node_destroy(&view->tree->node);
	free(view);
}
