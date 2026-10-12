/*
 * view.c: everything a window does regardless of whether it's a native
 * Wayland (xdg-shell) client or an X11 client through XWayland: focus,
 * stacking, placement, maximize/fullscreen/minimize, interactive move and
 * resize, and the foreign-toplevel handle the shell's rail uses.
 */

#include <stdlib.h>
#include <string.h>
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
	if (!view || !view->mapped || view->server->locked) {
		return;
	}
	struct ul_server *server = view->server;
	if (view->minimized) {
		view_set_minimized(view, false);
	}

	struct ul_view *prev = server->focused_view;
	/* Fullscreen stays on top only while focused (like Windows): when a
	 * game's own sign-in window or anything else gets focus, the
	 * fullscreen window steps back into the normal window layer, and
	 * returns above the panels when it is focused again. */
	struct ul_view *other;
	wl_list_for_each(other, &server->views, link) {
		if (other != view && other->fullscreen &&
				other->tree->node.parent == server->layers[UL_LAYER_FULLSCREEN]) {
			wlr_scene_node_reparent(&other->tree->node, server->layers[UL_LAYER_VIEWS]);
		}
	}
	if (view->fullscreen && view->tree->node.parent != server->layers[UL_LAYER_FULLSCREEN]) {
		wlr_scene_node_reparent(&view->tree->node, server->layers[UL_LAYER_FULLSCREEN]);
	}
	wlr_scene_node_raise_to_top(&view->tree->node);
	server->focused_view = view; /* for the restack below; also set further down */
	xwayland_restack_unmanaged(server);
	server->focused_view = prev;
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
	/* wlroots' xdg scene helper already shifts the client's surfaces by its
	 * invisible margins, so the view tree's origin is the visible window. */
	wlr_scene_node_set_position(&view->tree->node, x, y);
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
		/* Clients with invisible shadow margins (Chromium, GTK) can move
		 * their geometry offset without resizing; the chrome must follow. */
		struct wlr_box geo = view_geometry_offset(view);
		view_set_position(view, view->x, view->y);
		if (geo.x != view->geo_x || geo.y != view->geo_y) {
			view->geo_x = geo.x;
			view->geo_y = geo.y;
			decoration_update(view);
		}
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
	struct wlr_box geo = view_geometry_offset(view);
	view->geo_x = geo.x;
	view->geo_y = geo.y;
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

/* Tiled edges tell CSD clients to square their corners (xdg_toplevel
 * set_tiled_*); X11 has no equivalent. */
static void view_set_tiled(struct ul_view *view, enum ul_snap side) {
	if (view->type != UL_VIEW_XDG) {
		return;
	}
	uint32_t edges = 0;
	if (side == UL_SNAP_LEFT) edges = WLR_EDGE_LEFT | WLR_EDGE_TOP | WLR_EDGE_BOTTOM;
	if (side == UL_SNAP_RIGHT) edges = WLR_EDGE_RIGHT | WLR_EDGE_TOP | WLR_EDGE_BOTTOM;
	wlr_xdg_toplevel_set_tiled(view->xdg_toplevel, edges);
}

/* Frame box (content + titlebar + border) of a snapped window: half, third
 * or two thirds of the area, flush with the left or right edge. Left and
 * right halves are floor/ceil so together they cover the area exactly. */
struct wlr_box view_snap_frame(struct wlr_box area, enum ul_snap side, int step) {
	int w;
	switch (step) {
	case 1: w = area.width / 3; break;
	case 2: w = area.width - area.width / 3; break;
	default: w = side == UL_SNAP_LEFT ? area.width / 2 : area.width - area.width / 2; break;
	}
	return (struct wlr_box){ side == UL_SNAP_LEFT ? area.x : area.x + area.width - w,
		area.y, w, area.height };
}

static void view_apply_snap(struct ul_view *view) {
	struct wlr_box area = output_box(view, true);
	struct wlr_box f = view_snap_frame(area, view->snapped, view->snap_step);
	int bar = view->ssd ? UL_TITLEBAR_H : 0;
	view_set_position(view, f.x + UL_BORDER, f.y + bar + UL_BORDER);
	view_request_size(view, f.width - 2 * UL_BORDER, f.height - bar - 2 * UL_BORDER);
	view_set_tiled(view, view->snapped);
	if (view->type == UL_VIEW_XDG && view->xdg_toplevel->base->initialized) {
		wlr_xdg_surface_schedule_configure(view->xdg_toplevel->base);
	}
}

/* Snap to the left/right of the output's usable area. A maximized window
 * keeps its pre-maximize geometry as the thing to restore to. */
void view_snap(struct ul_view *view, enum ul_snap side, int step) {
	if (view->fullscreen || !view->mapped || side == UL_SNAP_NONE) {
		return;
	}
	if (!view->snapped && !view->maximized) {
		view->saved = (struct wlr_box){ view->x, view->y, view->width, view->height };
	}
	if (view->maximized) {
		view->maximized = false;
		if (view->type == UL_VIEW_XDG) {
			wlr_xdg_toplevel_set_maximized(view->xdg_toplevel, false);
		} else {
			wlr_xwayland_surface_set_maximized(view->xwayland_surface, false, false);
		}
		if (view->foreign) {
			wlr_foreign_toplevel_handle_v1_set_maximized(view->foreign, false);
		}
	}
	view->snapped = side;
	view->snap_step = step % UL_SNAP_STEPS;
	view_apply_snap(view);
}

/* Forget the snap without moving or resizing (the user resized the window,
 * or it is about to be maximized). */
void view_clear_snap(struct ul_view *view) {
	if (!view->snapped) {
		return;
	}
	view->snapped = UL_SNAP_NONE;
	view->snap_step = 0;
	view_set_tiled(view, UL_SNAP_NONE);
	if (view->type == UL_VIEW_XDG && view->xdg_toplevel->base->initialized) {
		wlr_xdg_surface_schedule_configure(view->xdg_toplevel->base);
	}
}

void view_restore(struct ul_view *view) {
	if (view->maximized) {
		view_set_maximized(view, false);
	} else if (view->snapped) {
		view_clear_snap(view);
		view_set_position(view, view->saved.x, view->saved.y);
		view_request_size(view, view->saved.width, view->saved.height);
	}
}

void view_refit(struct ul_view *view) {
	if (view->maximized) {
		struct wlr_box saved = view->saved;
		view->maximized = false;
		view_set_maximized(view, true);
		view->saved = saved;
	} else if (view->snapped && !view->fullscreen) {
		view_apply_snap(view);
	}
}

/* Move a window so its frame lies inside area (used before snapping a
 * dragged window, so what Restore returns to is on screen). */
void view_clamp_into(struct ul_view *view, struct wlr_box area) {
	int bar = view->ssd ? UL_TITLEBAR_H : 0;
	int x = view->x, y = view->y;
	if (x + view->width + UL_BORDER > area.x + area.width) x = area.x + area.width - UL_BORDER - view->width;
	if (y + view->height + UL_BORDER > area.y + area.height) y = area.y + area.height - UL_BORDER - view->height;
	if (x < area.x + UL_BORDER) x = area.x + UL_BORDER;
	if (y < area.y + bar + UL_BORDER) y = area.y + bar + UL_BORDER;
	view_set_position(view, x, y);
}

struct ul_view *view_by_id(struct ul_server *server, unsigned id) {
	struct ul_view *view;
	wl_list_for_each(view, &server->views, link) {
		if (view->id == id) return view;
	}
	return NULL;
}

void view_set_maximized(struct ul_view *view, bool maximized) {
	if (view->fullscreen || view->maximized == maximized) {
		goto done;
	}
	if (maximized) {
		if (view->snapped) {
			/* Keep the geometry from before the snap as the restore target. */
			view->snapped = UL_SNAP_NONE;
			view->snap_step = 0;
			view_set_tiled(view, UL_SNAP_NONE);
		} else {
			view->saved = (struct wlr_box){ view->x, view->y, view->width, view->height };
		}
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
		if (!view->maximized && !view->snapped) {
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
		} else if (view->snapped) {
			view_apply_snap(view);
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
	idle_update_inhibit(server);
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
	if (minimized) {
		wlr_scene_node_set_enabled(&view->tree->node, false);
		if (view->mapped) anim_minimize(view, true);
	} else if (view->mapped) {
		anim_minimize(view, false); /* shows the tree when it lands */
	} else {
		wlr_scene_node_set_enabled(&view->tree->node, true);
	}
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

/* Super+D. First press minimizes every visible window and remembers them
 * (most recently focused first); the next press, once nothing is visible,
 * brings exactly those back, restoring the old stacking order and focus.
 * If something was opened or restored in between, the press hides that too
 * and adds it to the set. */
void view_show_desktop(struct ul_server *server) {
	unsigned order[UL_DESKTOP_MAX];
	int n = 0;
	struct ul_view *view;
	wl_list_for_each(view, &server->views, link) {
		if (view->mapped && !view->minimized && n < UL_DESKTOP_MAX) {
			order[n++] = view->id;
		}
	}
	if (n > 0) {
		/* Merge with whatever an earlier press recorded, keeping ours first. */
		unsigned merged[UL_DESKTOP_MAX];
		int m = 0;
		for (int i = 0; i < n; i++) merged[m++] = order[i];
		for (int i = 0; i < server->desktop_n && m < UL_DESKTOP_MAX; i++) {
			bool dup = false;
			for (int j = 0; j < n; j++) dup |= order[j] == server->desktop_ids[i];
			if (!dup) merged[m++] = server->desktop_ids[i];
		}
		for (int i = 0; i < n; i++) {
			struct ul_view *v = view_by_id(server, order[i]);
			if (v) view_set_minimized(v, true);
		}
		memcpy(server->desktop_ids, merged, m * sizeof(unsigned));
		server->desktop_n = m;
		return;
	}
	/* Restore least recently focused first so the original top window ends up on top. */
	int count = server->desktop_n;
	server->desktop_n = 0;
	for (int i = count - 1; i >= 0; i--) {
		struct ul_view *v = view_by_id(server, server->desktop_ids[i]);
		if (v && v->mapped && v->minimized) {
			view_focus(v);
		}
	}
}

void view_close(struct ul_view *view) {
	anim_close_requested(view);
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
	/* A maximized window only restores once it's actually dragged (see
	 * process_move); restoring on press broke clicks and double-clicks. */
	server->restore_on_drag = mode == UL_CURSOR_MOVE && (view->maximized || view->snapped);
	if (mode == UL_CURSOR_RESIZE) {
		view_clear_snap(view); /* a hand-resized window is no longer a tile */
	}
	server->press_x = server->cursor->x;
	server->press_y = server->cursor->y;
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
	if (view->ext_foreign) {
		wlr_ext_foreign_toplevel_handle_v1_update_state(view->ext_foreign,
			&(struct wlr_ext_foreign_toplevel_handle_v1_state){
				.title = view_title(view), .app_id = view_app_id(view) });
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

/* The shell's rail tells us where this window's WINDOWS entry is, for the
 * minimize/restore animation. The rectangle is relative to the rail's
 * layer surface. */
static void foreign_set_rectangle(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, foreign_set_rectangle);
	struct wlr_foreign_toplevel_handle_v1_set_rectangle_event *event = data;
	view->has_rail_rect = false;
	if (!event->surface || event->width <= 0 || event->height <= 0) {
		return;
	}
	struct ul_output *output;
	wl_list_for_each(output, &view->server->outputs, link) {
		for (int i = 0; i < 4; i++) {
			struct ul_layer_surface *l;
			wl_list_for_each(l, &output->layer_surfaces[i], link) {
				if (l->layer_surface->surface != event->surface) continue;
				int lx, ly;
				if (!wlr_scene_node_coords(&l->scene->tree->node, &lx, &ly)) return;
				view->rail_rect = (struct wlr_box){ lx + event->x, ly + event->y,
					event->width, event->height };
				view->has_rail_rect = true;
				return;
			}
		}
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
	view->foreign_set_rectangle.notify = foreign_set_rectangle;
	wl_signal_add(&view->foreign->events.set_rectangle, &view->foreign_set_rectangle);
	/* The same window for screen capture (ext-foreign-toplevel-list). */
	view->ext_foreign = wlr_ext_foreign_toplevel_handle_v1_create(view->server->ext_toplevel_list,
		&(struct wlr_ext_foreign_toplevel_handle_v1_state){
			.title = view_title(view), .app_id = view_app_id(view) });
	if (view->ext_foreign) {
		view->ext_foreign->data = view;
	}
	view_update_title(view);
}

static void finish_foreign(struct ul_view *view) {
	/* Capture sources die with the handle they were made from. */
	capture_view_destroy(view);
	if (view->ext_foreign) {
		wlr_ext_foreign_toplevel_handle_v1_destroy(view->ext_foreign);
		view->ext_foreign = NULL;
	}
	if (!view->foreign) {
		return;
	}
	wl_list_remove(&view->foreign_activate.link);
	wl_list_remove(&view->foreign_close.link);
	wl_list_remove(&view->foreign_minimize.link);
	wl_list_remove(&view->foreign_maximize.link);
	wl_list_remove(&view->foreign_fullscreen.link);
	wl_list_remove(&view->foreign_set_rectangle.link);
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
	 * the shell's panels leave free. Windows that would land exactly on top
	 * of another one step down-right so nothing hides behind a twin. */
	struct ul_output *output = output_at(server, server->cursor->x, server->cursor->y);
	if (output) {
		struct wlr_box area = output->usable_area;
		int bar = view->ssd ? UL_TITLEBAR_H : 0;
		int max_w = area.width - 2 * UL_BORDER;
		int max_h = area.height - bar - 2 * UL_BORDER;
		if (view->width > max_w || view->height > max_h) {
			/* Too big for the free area (e.g. sized for a bigger screen). */
			view->width = view->width > max_w ? max_w : view->width;
			view->height = view->height > max_h ? max_h : view->height;
			view_request_size(view, view->width, view->height);
		}
		int x = area.x + (area.width - view->width) / 2;
		int y = area.y + bar + (area.height - bar - view->height) / 2;
		for (int tries = 0; tries < 12; tries++) {
			bool taken = false;
			struct ul_view *other;
			wl_list_for_each(other, &server->views, link) {
				if (other != view && other->mapped && !other->minimized &&
						abs(other->x - x) < 24 && abs(other->y - y) < 24) {
					taken = true;
					break;
				}
			}
			if (!taken) break;
			x += 36;
			y += 36;
			if (x + view->width > area.x + area.width || y + view->height > area.y + area.height) {
				x = area.x + 24 * (tries + 1);
				y = area.y + bar + 24 * (tries + 1);
			}
		}
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
	anim_open(view);
	anim_track_commits(view, true);
}

void view_unmap(struct ul_view *view) {
	struct ul_server *server = view->server;
	anim_cancel(view);
	anim_close(view);
	anim_track_commits(view, false);
	view->mapped = false;
	wlr_scene_node_set_enabled(&view->tree->node, false);
	finish_foreign(view);
	if (server->grabbed_view == view) {
		server->cursor_mode = UL_CURSOR_PASSTHROUGH;
		server->grabbed_view = NULL;
		input_snap_preview_hide(server);
	}
	alttab_view_gone(server, view->id);
	if (server->last_click_view == view) {
		server->last_click_view = NULL;
	}
	wl_list_remove(&view->link);
	wl_list_init(&view->link);
	idle_update_inhibit(server);
	if (server->focused_view == view) {
		server->focused_view = NULL;
		focus_topmost(server);
	}
}

void view_destroy(struct ul_view *view) {
	anim_view_destroyed(view);
	finish_foreign(view);
	if (view->xdg_decoration) {
		wl_list_remove(&view->decoration_request_mode.link);
		wl_list_remove(&view->decoration_destroy.link);
	}
	wl_list_remove(&view->link);
	wlr_scene_node_destroy(&view->tree->node);
	free(view->deco.drawn_title);
	free(view);
}
