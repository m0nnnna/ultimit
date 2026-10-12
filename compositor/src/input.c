/*
 * input.c: keyboards, pointers and the cursor. Games need two things from
 * here beyond the basics: relative pointer motion (mouse-look) and pointer
 * constraints (locking or confining the cursor to the game window).
 */

#include <stdlib.h>
#include <time.h>
#include <linux/input-event-codes.h>
#include <wlr/types/wlr_cursor_shape_v1.h>
#include <wlr/types/wlr_data_device.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_pointer.h>
#include <wlr/types/wlr_primary_selection.h>
#include <wlr/types/wlr_virtual_keyboard_v1.h>
#include <wlr/types/wlr_virtual_pointer_v1.h>
#include <wlr/util/region.h>
#include <xkbcommon/xkbcommon.h>
#include "server.h"
#include "theme.h"

struct ul_keyboard {
	struct wl_list link;
	struct ul_server *server;
	struct wlr_keyboard *wlr_keyboard;
	bool virtual; /* wtype etc.: keeps the keymap it uploads */
	struct wl_listener modifiers;
	struct wl_listener key;
	struct wl_listener destroy;
};

/* ---- focus helpers ------------------------------------------------------- */

void input_focus_layer(struct ul_server *server, struct wlr_layer_surface_v1 *layer_surface) {
	if (server->locked) {
		return;
	}
	server->focused_layer = layer_surface;
	if (!layer_surface) {
		if (server->focused_view) {
			struct ul_view *view = server->focused_view;
			server->focused_view = NULL;
			view_focus(view);
		} else {
			wlr_seat_keyboard_notify_clear_focus(server->seat);
		}
		return;
	}
	struct wlr_keyboard *keyboard = wlr_seat_get_keyboard(server->seat);
	wlr_seat_keyboard_notify_enter(server->seat, layer_surface->surface,
		keyboard ? keyboard->keycodes : NULL, keyboard ? keyboard->num_keycodes : 0,
		keyboard ? &keyboard->modifiers : NULL);
}

/* Finds the surface under the cursor, and the view it belongs to if any. */
static struct wlr_surface *surface_at(struct ul_server *server, double lx, double ly,
		double *sx, double *sy, struct ul_view **view_out, struct wlr_scene_node **node_out) {
	*view_out = NULL;
	/* While locked, only the lock screen can be hit. */
	struct wlr_scene_node *root = server->locked ?
		&server->layers[UL_LAYER_LOCK]->node : &server->scene->tree.node;
	struct wlr_scene_node *node = wlr_scene_node_at(root, lx, ly, sx, sy);
	if (node_out) *node_out = node;
	if (!node) {
		return NULL;
	}
	*view_out = view_from_node(node);
	if (node->type != WLR_SCENE_NODE_BUFFER) {
		return NULL;
	}
	struct wlr_scene_surface *scene_surface =
		wlr_scene_surface_try_from_buffer(wlr_scene_buffer_from_node(node));
	return scene_surface ? scene_surface->surface : NULL;
}

/* Edges of a view the cursor is grabbing, if it's just outside the content. */
static uint32_t resize_edges_at(struct ul_view *view, double lx, double ly) {
	if (!view || !view->mapped || view->fullscreen || view->maximized) {
		return 0;
	}
	int bar = view->ssd ? UL_TITLEBAR_H : 0;
	int m = UL_RESIZE_MARGIN;
	double left = view->x, right = view->x + view->width;
	double top = view->y - bar, bottom = view->y + view->height;
	if (lx < left - m || lx > right + m || ly < top - m || ly > bottom + m) {
		return 0;
	}
	uint32_t edges = 0;
	if (lx < left + 1) edges |= WLR_EDGE_LEFT;
	else if (lx > right - 1) edges |= WLR_EDGE_RIGHT;
	if (ly < top + 1) edges |= WLR_EDGE_TOP;
	else if (ly > bottom - 1) edges |= WLR_EDGE_BOTTOM;
	return edges;
}

static struct ul_view *view_edge_at(struct ul_server *server, double lx, double ly,
		uint32_t *edges) {
	struct ul_view *view;
	wl_list_for_each(view, &server->views, link) {
		if (view->minimized) continue;
		*edges = resize_edges_at(view, lx, ly);
		if (*edges) return view;
	}
	return NULL;
}

static const char *edge_cursor(uint32_t edges) {
	switch (edges) {
	case WLR_EDGE_TOP: return "n-resize";
	case WLR_EDGE_BOTTOM: return "s-resize";
	case WLR_EDGE_LEFT: return "w-resize";
	case WLR_EDGE_RIGHT: return "e-resize";
	case WLR_EDGE_TOP | WLR_EDGE_LEFT: return "nw-resize";
	case WLR_EDGE_TOP | WLR_EDGE_RIGHT: return "ne-resize";
	case WLR_EDGE_BOTTOM | WLR_EDGE_LEFT: return "sw-resize";
	case WLR_EDGE_BOTTOM | WLR_EDGE_RIGHT: return "se-resize";
	default: return "default";
	}
}

/* ---- pointer constraints ------------------------------------------------- */

static void constraint_destroy(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, constraint_destroy);
	struct wlr_pointer_constraint_v1 *constraint = data;
	if (server->active_constraint == constraint) {
		wl_list_remove(&server->constraint_destroy.link);
		wl_list_init(&server->constraint_destroy.link);
		server->active_constraint = NULL;
	}
}

static void activate_constraint(struct ul_server *server,
		struct wlr_pointer_constraint_v1 *constraint) {
	if (server->active_constraint == constraint) {
		return;
	}
	if (server->active_constraint) {
		wlr_pointer_constraint_v1_send_deactivated(server->active_constraint);
		wl_list_remove(&server->constraint_destroy.link);
		wl_list_init(&server->constraint_destroy.link);
	}
	server->active_constraint = constraint;
	if (constraint) {
		wlr_pointer_constraint_v1_send_activated(constraint);
		server->constraint_destroy.notify = constraint_destroy;
		wl_signal_add(&constraint->events.destroy, &server->constraint_destroy);
	}
}

static void check_constraint(struct ul_server *server, struct wlr_surface *focused) {
	struct wlr_pointer_constraint_v1 *constraint = focused ?
		wlr_pointer_constraints_v1_constraint_for_surface(
			server->pointer_constraints, focused, server->seat) : NULL;
	/* Only the window with keyboard focus may grab the pointer. */
	if (constraint && server->seat->keyboard_state.focused_surface != focused) {
		constraint = NULL;
	}
	activate_constraint(server, constraint);
}

static void new_constraint(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, new_constraint);
	struct wlr_pointer_constraint_v1 *constraint = data;
	if (server->seat->pointer_state.focused_surface == constraint->surface) {
		check_constraint(server, constraint->surface);
	}
}

/* ---- cursor -------------------------------------------------------------- */

void input_update_pointer_focus(struct ul_server *server, uint32_t time_msec) {
	if (time_msec == 0) {
		struct timespec now;
		clock_gettime(CLOCK_MONOTONIC, &now);
		time_msec = now.tv_sec * 1000 + now.tv_nsec / 1000000;
	}
	double sx, sy;
	struct ul_view *view;
	struct wlr_surface *surface = surface_at(server, server->cursor->x, server->cursor->y,
		&sx, &sy, &view, NULL);
	if (surface) {
		wlr_seat_pointer_notify_enter(server->seat, surface, sx, sy);
		wlr_seat_pointer_notify_motion(server->seat, time_msec, sx, sy);
	} else {
		uint32_t edges = 0;
		view_edge_at(server, server->cursor->x, server->cursor->y, &edges);
		wlr_cursor_set_xcursor(server->cursor, server->cursor_mgr, edge_cursor(edges));
		wlr_seat_pointer_clear_focus(server->seat);
	}
	check_constraint(server, surface);
}

/* ---- drag-to-snap ----------------------------------------------------------- */

static void preview_rects(struct ul_server *server, struct wlr_box box) {
	static const float fill[4] = { 212 / 255.0f * 0.22f, 235 / 255.0f * 0.22f, 1.0f * 0.22f, 0.22f };
	static const float edge[4] = { 212 / 255.0f * 0.85f, 235 / 255.0f * 0.85f, 1.0f * 0.85f, 0.85f };
	const int t = 2;
	if (!server->snap_preview) {
		server->snap_preview = wlr_scene_tree_create(server->layers[UL_LAYER_GHOSTS]);
		server->snap_preview_rects[0] = wlr_scene_rect_create(server->snap_preview, 1, 1, fill);
		for (int i = 1; i < 5; i++) {
			server->snap_preview_rects[i] = wlr_scene_rect_create(server->snap_preview, 1, 1, edge);
		}
	}
	wlr_scene_node_set_position(&server->snap_preview->node, box.x, box.y);
	struct { int x, y, w, h; } r[5] = {
		{ 0, 0, box.width, box.height },
		{ 0, 0, box.width, t }, { 0, box.height - t, box.width, t },
		{ 0, 0, t, box.height }, { box.width - t, 0, t, box.height },
	};
	for (int i = 0; i < 5; i++) {
		wlr_scene_rect_set_size(server->snap_preview_rects[i], r[i].w, r[i].h);
		wlr_scene_node_set_position(&server->snap_preview_rects[i]->node, r[i].x, r[i].y);
	}
	wlr_scene_node_set_enabled(&server->snap_preview->node, true);
}

void input_snap_preview_hide(struct ul_server *server) {
	server->snap_zone = UL_ZONE_NONE;
	server->snap_zone_output = NULL;
	if (server->snap_preview) {
		wlr_scene_node_set_enabled(&server->snap_preview->node, false);
	}
}

/* Where would the dragged window land if released now? Left/right screen
 * edge: that half of the output; top edge: maximized. Edges shared with
 * another output don't count, so crossing monitors never snaps. */
static void update_snap_zone(struct ul_server *server) {
	double cx = server->cursor->x, cy = server->cursor->y;
	struct ul_output *out = output_at(server, cx, cy);
	enum ul_snap_zone zone = UL_ZONE_NONE;
	if (out && server->grabbed_view && !server->grabbed_view->fullscreen) {
		struct wlr_box a = out->full_area;
		if (cx <= a.x + UL_SNAP_EDGE && !output_at(server, a.x - 1, cy)) {
			zone = UL_ZONE_LEFT;
		} else if (cx >= a.x + a.width - 1 - UL_SNAP_EDGE &&
				!output_at(server, a.x + a.width, cy)) {
			zone = UL_ZONE_RIGHT;
		} else if (cy <= a.y + UL_SNAP_EDGE && !output_at(server, cx, a.y - 1)) {
			zone = UL_ZONE_MAXIMIZE;
		}
	}
	if (zone == server->snap_zone && out == server->snap_zone_output) {
		return;
	}
	if (zone == UL_ZONE_NONE) {
		input_snap_preview_hide(server);
		return;
	}
	server->snap_zone = zone;
	server->snap_zone_output = out;
	struct wlr_box box = out->usable_area;
	if (zone != UL_ZONE_MAXIMIZE) {
		box = view_snap_frame(box, zone == UL_ZONE_LEFT ? UL_SNAP_LEFT : UL_SNAP_RIGHT, 0);
	}
	preview_rects(server, box);
}

static void apply_snap_zone(struct ul_server *server) {
	struct ul_view *view = server->grabbed_view;
	enum ul_snap_zone zone = server->snap_zone;
	struct ul_output *out = server->snap_zone_output;
	input_snap_preview_hide(server);
	if (!view || !out || zone == UL_ZONE_NONE || !view->mapped) {
		return;
	}
	/* What Restore returns to should be on screen, on the target output. */
	if (!view->maximized && !view->snapped) {
		view_clamp_into(view, out->usable_area);
	}
	if (zone == UL_ZONE_MAXIMIZE) {
		view_set_maximized(view, true);
	} else {
		view_snap(view, zone == UL_ZONE_LEFT ? UL_SNAP_LEFT : UL_SNAP_RIGHT, 0);
	}
}

static void process_move(struct ul_server *server) {
	struct ul_view *view = server->grabbed_view;
	if (server->restore_on_drag) {
		double dx = server->cursor->x - server->press_x;
		double dy = server->cursor->y - server->press_y;
		if (dx * dx + dy * dy < 8 * 8) {
			return; /* still a click, not a drag */
		}
		/* Restore under the pointer, keeping the same relative grab point. */
		server->restore_on_drag = false;
		double rel = (server->press_x - view->x) / (double)(view->width ? view->width : 1);
		int grab_y = server->press_y - view->y;
		view_restore(view);
		server->grab_x = rel * view->saved.width;
		server->grab_y = grab_y;
	}
	view_set_position(view, server->cursor->x - server->grab_x,
		server->cursor->y - server->grab_y);
	update_snap_zone(server);
}

static void process_resize(struct ul_server *server) {
	struct ul_view *view = server->grabbed_view;
	double bx = server->cursor->x - server->grab_x;
	double by = server->cursor->y - server->grab_y;
	struct wlr_box *g = &server->grab_box;
	int left = g->x, right = g->x + g->width, top = g->y, bottom = g->y + g->height;
	uint32_t edges = server->resize_edges;
	if (edges & WLR_EDGE_TOP) {
		top = by < bottom - 1 ? by : bottom - 1;
	} else if (edges & WLR_EDGE_BOTTOM) {
		bottom = by > top + 1 ? by : top + 1;
	}
	if (edges & WLR_EDGE_LEFT) {
		left = bx < right - 1 ? bx : right - 1;
	} else if (edges & WLR_EDGE_RIGHT) {
		right = bx > left + 1 ? bx : left + 1;
	}
	if (view->type == UL_VIEW_XWAYLAND) {
		/* X clients take position and size together. */
		view->x = left;
		view->y = top;
	}
	view_request_size(view, right - left, bottom - top);
}

static void process_motion(struct ul_server *server, uint32_t time_msec) {
	if (server->cursor_mode == UL_CURSOR_MOVE) {
		process_move(server);
		return;
	}
	if (server->cursor_mode == UL_CURSOR_RESIZE) {
		process_resize(server);
		return;
	}
	input_update_pointer_focus(server, time_msec);
}

static void handle_motion(struct ul_server *server, struct wlr_input_device *device,
		uint32_t time_msec, double dx, double dy, double udx, double udy) {
	idle_activity(server);
	wlr_relative_pointer_manager_v1_send_relative_motion(server->relative_pointer,
		server->seat, (uint64_t)time_msec * 1000, dx, dy, udx, udy);

	struct wlr_pointer_constraint_v1 *constraint = server->active_constraint;
	if (constraint && server->cursor_mode == UL_CURSOR_PASSTHROUGH) {
		if (constraint->type == WLR_POINTER_CONSTRAINT_V1_LOCKED) {
			/* Locked: the game only gets relative motion. */
			return;
		}
		double sx, sy;
		struct ul_view *view;
		struct wlr_surface *surface = surface_at(server, server->cursor->x,
			server->cursor->y, &sx, &sy, &view, NULL);
		if (surface == constraint->surface) {
			double cx, cy;
			if (wlr_region_confine(&constraint->region, sx, sy, sx + dx, sy + dy, &cx, &cy)) {
				dx = cx - sx;
				dy = cy - sy;
			}
		}
	}
	wlr_cursor_move(server->cursor, device, dx, dy);
	process_motion(server, time_msec);
}

static void cursor_motion(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, cursor_motion);
	struct wlr_pointer_motion_event *event = data;
	handle_motion(server, &event->pointer->base, event->time_msec,
		event->delta_x, event->delta_y, event->unaccel_dx, event->unaccel_dy);
}

static void cursor_motion_absolute(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, cursor_motion_absolute);
	struct wlr_pointer_motion_absolute_event *event = data;
	double lx, ly;
	wlr_cursor_absolute_to_layout_coords(server->cursor, &event->pointer->base,
		event->x, event->y, &lx, &ly);
	double dx = lx - server->cursor->x, dy = ly - server->cursor->y;
	handle_motion(server, &event->pointer->base, event->time_msec, dx, dy, dx, dy);
}

static void end_interactive(struct ul_server *server) {
	struct ul_view *view = server->grabbed_view;
	if (view && server->cursor_mode == UL_CURSOR_RESIZE && view->type == UL_VIEW_XDG) {
		wlr_xdg_toplevel_set_resizing(view->xdg_toplevel, false);
	}
	server->cursor_mode = UL_CURSOR_PASSTHROUGH;
	server->grabbed_view = NULL;
	server->restore_on_drag = false;
	input_snap_preview_hide(server);
}

/* Button released (or the test hook's drop): snap if over a zone, then stop. */
static void finish_grab(struct ul_server *server) {
	if (server->cursor_mode == UL_CURSOR_MOVE) {
		apply_snap_zone(server);
	}
	end_interactive(server);
}

static bool alt_held(struct ul_server *server) {
	struct wlr_keyboard *keyboard = wlr_seat_get_keyboard(server->seat);
	return keyboard && (wlr_keyboard_get_modifiers(keyboard) & (WLR_MODIFIER_ALT | WLR_MODIFIER_LOGO));
}

static void cursor_button(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, cursor_button);
	server->super_tap = false; /* Super+click isn't a tap */
	struct wlr_pointer_button_event *event = data;
	idle_activity(server);
	if (server->locked) {
		wlr_seat_pointer_notify_button(server->seat, event->time_msec,
			event->button, event->state);
		return;
	}

	if (event->state == WL_POINTER_BUTTON_STATE_RELEASED) {
		/* Always pass the release on. A client that asked to be moved or
		 * resized on press (xdg move/resize, Qt drag areas) got that press;
		 * if it never sees the release, the seat keeps the button "held"
		 * and every later click stays stuck on that surface. */
		wlr_seat_pointer_notify_button(server->seat, event->time_msec,
			event->button, event->state);
		if (server->cursor_mode != UL_CURSOR_PASSTHROUGH) {
			finish_grab(server);
		}
		return;
	}

	double sx, sy;
	struct ul_view *view;
	struct wlr_surface *surface = surface_at(server, server->cursor->x, server->cursor->y,
		&sx, &sy, &view, NULL);

	/* Clicking an override-redirect X11 window (a game's sign-in overlay)
	 * gives it the keyboard; the window under it keeps its stacking. */
	if (surface && xwayland_focus_unmanaged(server, surface)) {
		wlr_seat_pointer_notify_button(server->seat, event->time_msec,
			event->button, event->state);
		return;
	}

	/* Clicking a layer surface that takes keyboard input focuses it. */
	if (surface) {
		struct wlr_layer_surface_v1 *layer =
			wlr_layer_surface_v1_try_from_wlr_surface(wlr_surface_get_root_surface(surface));
		if (layer && layer->current.keyboard_interactive !=
				ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE) {
			input_focus_layer(server, layer);
		} else if (!layer && server->focused_layer &&
				server->focused_layer->current.keyboard_interactive ==
				ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND) {
			server->focused_layer = NULL;
		}
	}

	if (view) {
		view_focus(view);
		/* Alt/Super + drag moves, Alt/Super + right-drag resizes. */
		if (alt_held(server) && !view->fullscreen) {
			if (event->button == BTN_LEFT) {
				view_begin_interactive(view, UL_CURSOR_MOVE, 0);
				return;
			}
			if (event->button == BTN_RIGHT) {
				uint32_t edges = 0;
				edges |= server->cursor->x < view->x + view->width / 2 ? WLR_EDGE_LEFT : WLR_EDGE_RIGHT;
				edges |= server->cursor->y < view->y + view->height / 2 ? WLR_EDGE_TOP : WLR_EDGE_BOTTOM;
				view_begin_interactive(view, UL_CURSOR_RESIZE, edges);
				return;
			}
		}
		if (!surface && event->button == BTN_LEFT) {
			switch (decoration_hit(view, server->cursor->x, server->cursor->y)) {
			case UL_HIT_CLOSE:
				view_close(view);
				return;
			case UL_HIT_MAXIMIZE:
				view_set_maximized(view, !view->maximized);
				return;
			case UL_HIT_MINIMIZE:
				view_set_minimized(view, true);
				return;
			case UL_HIT_TITLE:
				if (server->last_click_view == view &&
						event->time_msec - server->last_click_msec < 400) {
					server->last_click_view = NULL;
					view_set_maximized(view, !view->maximized);
					return;
				}
				server->last_click_view = view;
				server->last_click_msec = event->time_msec;
				view_begin_interactive(view, UL_CURSOR_MOVE, 0);
				return;
			case UL_HIT_NONE:
				break;
			}
		}
	}

	if (!surface && event->button == BTN_LEFT) {
		uint32_t edges = 0;
		struct ul_view *edge_view = view_edge_at(server, server->cursor->x,
			server->cursor->y, &edges);
		if (edge_view) {
			view_focus(edge_view);
			view_begin_interactive(edge_view, UL_CURSOR_RESIZE, edges);
			return;
		}
	}

	wlr_seat_pointer_notify_button(server->seat, event->time_msec,
		event->button, event->state);
}

static void cursor_axis(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, cursor_axis);
	struct wlr_pointer_axis_event *event = data;
	idle_activity(server);
	wlr_seat_pointer_notify_axis(server->seat, event->time_msec, event->orientation,
		event->delta, event->delta_discrete, event->source, event->relative_direction);
}

static void cursor_frame(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, cursor_frame);
	wlr_seat_pointer_notify_frame(server->seat);
}

static void request_set_shape(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, request_set_shape);
	struct wlr_cursor_shape_manager_v1_request_set_shape_event *event = data;
	if (server->cursor_mode == UL_CURSOR_PASSTHROUGH &&
			event->seat_client == server->seat->pointer_state.focused_client) {
		wlr_cursor_set_xcursor(server->cursor, server->cursor_mgr,
			wlr_cursor_shape_v1_name(event->shape));
	}
}

/* Test hook (ultimitctl drag / drag-release): drive the real titlebar-drag
 * path without a pointer that can hold a button. The first call grabs the
 * window by the middle of its titlebar; every call then walks the pointer to
 * layout X,Y in small steps. Release (or view == NULL) drops it. */
void input_test_drag(struct ul_server *server, struct ul_view *view, int x, int y, bool release) {
	if (release) {
		if (server->cursor_mode != UL_CURSOR_PASSTHROUGH) finish_grab(server);
		return;
	}
	if (server->cursor_mode != UL_CURSOR_MOVE || server->grabbed_view != view) {
		int bar = view->ssd ? UL_TITLEBAR_H : 0;
		wlr_cursor_warp_closest(server->cursor, NULL, view->x + view->width / 2.0,
			view->y - bar / 2.0 + (bar ? 0 : 10));
		view_focus(view);
		view_begin_interactive(view, UL_CURSOR_MOVE, 0);
	}
	double sx = server->cursor->x, sy = server->cursor->y;
	for (int i = 1; i <= 12; i++) {
		wlr_cursor_warp_closest(server->cursor, NULL, sx + (x - sx) * i / 12.0, sy + (y - sy) * i / 12.0);
		process_motion(server, 0);
	}
}

/* ---- keyboard ------------------------------------------------------------ */

static void keyboard_key(struct wl_listener *listener, void *data) {
	struct ul_keyboard *keyboard = wl_container_of(listener, keyboard, key);
	struct ul_server *server = keyboard->server;
	struct wlr_keyboard_key_event *event = data;
	idle_activity(server);

	/* Super tapped on its own (no other key or click while held) opens the
	 * launcher; Super+key shortcuts don't. */
	xkb_keysym_t key_sym = xkb_state_key_get_one_sym(keyboard->wlr_keyboard->xkb_state,
		event->keycode + 8);
	bool is_super = key_sym == XKB_KEY_Super_L || key_sym == XKB_KEY_Super_R;
	if (event->state == WL_KEYBOARD_KEY_STATE_PRESSED) {
		server->super_tap = is_super;
	} else if (is_super) {
		if (server->super_tap && !server->locked) {
			keys_super_tap(server);
		}
		server->super_tap = false;
	}

	bool handled = false;
	if (event->state == WL_KEYBOARD_KEY_STATE_PRESSED) {
		uint32_t mods = wlr_keyboard_get_modifiers(keyboard->wlr_keyboard);
		const xkb_keysym_t *syms;
		int nsyms = xkb_state_key_get_syms(keyboard->wlr_keyboard->xkb_state,
			event->keycode + 8, &syms);
		for (int i = 0; i < nsyms && !handled; i++) {
			handled = keys_handle(server, mods, syms[i]);
		}
	}
	if (!handled) {
		wlr_seat_set_keyboard(server->seat, keyboard->wlr_keyboard);
		wlr_seat_keyboard_notify_key(server->seat, event->time_msec,
			event->keycode, event->state);
	}
}

static void keyboard_modifiers(struct wl_listener *listener, void *data) {
	struct ul_keyboard *keyboard = wl_container_of(listener, keyboard, modifiers);
	alttab_modifiers(keyboard->server, wlr_keyboard_get_modifiers(keyboard->wlr_keyboard));
	wlr_seat_set_keyboard(keyboard->server->seat, keyboard->wlr_keyboard);
	wlr_seat_keyboard_notify_modifiers(keyboard->server->seat,
		&keyboard->wlr_keyboard->modifiers);
}

static void keyboard_destroy(struct wl_listener *listener, void *data) {
	struct ul_keyboard *keyboard = wl_container_of(listener, keyboard, destroy);
	/* Its release of Alt/Super will never arrive: don't leave the switcher open. */
	alttab_cancel(keyboard->server);
	wl_list_remove(&keyboard->modifiers.link);
	wl_list_remove(&keyboard->key.link);
	wl_list_remove(&keyboard->destroy.link);
	wl_list_remove(&keyboard->link);
	free(keyboard);
}

static void new_keyboard(struct ul_server *server, struct wlr_input_device *device,
		bool virtual) {
	struct wlr_keyboard *wlr_keyboard = wlr_keyboard_from_input_device(device);
	struct ul_keyboard *keyboard = calloc(1, sizeof(*keyboard));
	keyboard->server = server;
	keyboard->wlr_keyboard = wlr_keyboard;

	/* Layout comes from XKB_DEFAULT_LAYOUT etc. in the environment. Virtual
	 * keyboards (wtype, remote input) upload their own keymap. */
	keyboard->virtual = virtual;
	if (!virtual) {
		config_apply_keyboard(server, wlr_keyboard);
	}

	keyboard->modifiers.notify = keyboard_modifiers;
	wl_signal_add(&wlr_keyboard->events.modifiers, &keyboard->modifiers);
	keyboard->key.notify = keyboard_key;
	wl_signal_add(&wlr_keyboard->events.key, &keyboard->key);
	keyboard->destroy.notify = keyboard_destroy;
	wl_signal_add(&device->events.destroy, &keyboard->destroy);

	wlr_seat_set_keyboard(server->seat, wlr_keyboard);
	wl_list_insert(&server->keyboards, &keyboard->link);
}

static void pointer_destroy(struct wl_listener *listener, void *data) {
	struct ul_pointer *p = wl_container_of(listener, p, destroy);
	wl_list_remove(&p->link);
	wl_list_remove(&p->destroy.link);
	free(p);
}

void input_reapply_keyboards(struct ul_server *server) {
	struct ul_keyboard *keyboard;
	wl_list_for_each(keyboard, &server->keyboards, link) {
		if (!keyboard->virtual) {
			config_apply_keyboard(server, keyboard->wlr_keyboard);
		}
	}
}

static void add_input_device(struct ul_server *server, struct wlr_input_device *device,
		bool virtual) {
	switch (device->type) {
	case WLR_INPUT_DEVICE_KEYBOARD:
		new_keyboard(server, device, virtual);
		break;
	case WLR_INPUT_DEVICE_POINTER: {
		struct ul_pointer *p = calloc(1, sizeof(*p));
		p->device = device;
		p->destroy.notify = pointer_destroy;
		wl_signal_add(&device->events.destroy, &p->destroy);
		wl_list_insert(&server->pointers, &p->link);
		config_apply_pointer(server, device);
		wlr_cursor_attach_input_device(server->cursor, device);
		break;
	}
	default:
		break;
	}
	uint32_t caps = WL_SEAT_CAPABILITY_POINTER;
	if (!wl_list_empty(&server->keyboards)) {
		caps |= WL_SEAT_CAPABILITY_KEYBOARD;
	}
	wlr_seat_set_capabilities(server->seat, caps);
}

static void new_input(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, new_input);
	add_input_device(server, data, false);
}

/* Virtual input (wtype, wlrctl): lets scripted tests and remote tools drive
 * the desktop. Standard on wlroots compositors; to be limited to trusted
 * clients before Ultimit ships to other people. */
static void new_virtual_keyboard(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, new_virtual_keyboard);
	struct wlr_virtual_keyboard_v1 *keyboard = data;
	add_input_device(server, &keyboard->keyboard.base, true);
}

static void new_virtual_pointer(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, new_virtual_pointer);
	struct wlr_virtual_pointer_v1_new_pointer_event *event = data;
	struct wlr_input_device *device = &event->new_pointer->pointer.base;
	add_input_device(server, device, true);
	if (event->suggested_output) {
		wlr_cursor_map_input_to_output(server->cursor, device, event->suggested_output);
	}
}

/* ---- seat requests ------------------------------------------------------- */

static void request_cursor(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, request_cursor);
	struct wlr_seat_pointer_request_set_cursor_event *event = data;
	if (server->cursor_mode == UL_CURSOR_PASSTHROUGH &&
			event->seat_client == server->seat->pointer_state.focused_client) {
		wlr_cursor_set_surface(server->cursor, event->surface,
			event->hotspot_x, event->hotspot_y);
	}
}

static void request_set_selection(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, request_set_selection);
	struct wlr_seat_request_set_selection_event *event = data;
	wlr_seat_set_selection(server->seat, event->source, event->serial);
}

static void request_set_primary_selection(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, request_set_primary_selection);
	struct wlr_seat_request_set_primary_selection_event *event = data;
	wlr_seat_set_primary_selection(server->seat, event->source, event->serial);
}

/* Swap the cursor theme at runtime (skin change). Apps started later get
 * it through the environment; running clients mostly ask us to draw via
 * cursor-shape, so they follow at once. */
bool input_set_cursor_theme(struct ul_server *server, const char *name, int size) {
	if (size <= 0) {
		const char *env = getenv("XCURSOR_SIZE");
		size = env ? atoi(env) : 24;
	}
	struct wlr_xcursor_manager *mgr = wlr_xcursor_manager_create(name, size);
	if (!mgr || !wlr_xcursor_manager_load(mgr, 1)) {
		wlr_xcursor_manager_destroy(mgr);
		return false;
	}
	struct wlr_xcursor_manager *old = server->cursor_mgr;
	server->cursor_mgr = mgr;
	wlr_cursor_set_xcursor(server->cursor, mgr, "default");
	wlr_xcursor_manager_destroy(old);
	setenv("XCURSOR_THEME", name, true);
	char buf[16];
	snprintf(buf, sizeof(buf), "%d", size);
	setenv("XCURSOR_SIZE", buf, true);
	return true;
}

void input_init(struct ul_server *server) {
	server->cursor = wlr_cursor_create();
	wlr_cursor_attach_output_layout(server->cursor, server->output_layout);
	const char *size = getenv("XCURSOR_SIZE");
	server->cursor_mgr = wlr_xcursor_manager_create(getenv("XCURSOR_THEME"),
		size ? atoi(size) : 24);

	server->cursor_mode = UL_CURSOR_PASSTHROUGH;
	server->cursor_motion.notify = cursor_motion;
	wl_signal_add(&server->cursor->events.motion, &server->cursor_motion);
	server->cursor_motion_absolute.notify = cursor_motion_absolute;
	wl_signal_add(&server->cursor->events.motion_absolute, &server->cursor_motion_absolute);
	server->cursor_button.notify = cursor_button;
	wl_signal_add(&server->cursor->events.button, &server->cursor_button);
	server->cursor_axis.notify = cursor_axis;
	wl_signal_add(&server->cursor->events.axis, &server->cursor_axis);
	server->cursor_frame.notify = cursor_frame;
	wl_signal_add(&server->cursor->events.frame, &server->cursor_frame);

	struct wlr_cursor_shape_manager_v1 *shapes =
		wlr_cursor_shape_manager_v1_create(server->display, 1);
	server->request_set_shape.notify = request_set_shape;
	wl_signal_add(&shapes->events.request_set_shape, &server->request_set_shape);

	server->relative_pointer = wlr_relative_pointer_manager_v1_create(server->display);
	server->pointer_constraints = wlr_pointer_constraints_v1_create(server->display);
	server->new_constraint.notify = new_constraint;
	wl_signal_add(&server->pointer_constraints->events.new_constraint, &server->new_constraint);
	wl_list_init(&server->constraint_destroy.link);

	wl_list_init(&server->keyboards);
	wl_list_init(&server->pointers);
	server->new_input.notify = new_input;
	wl_signal_add(&server->backend->events.new_input, &server->new_input);

	struct wlr_virtual_keyboard_manager_v1 *vkbd =
		wlr_virtual_keyboard_manager_v1_create(server->display);
	server->new_virtual_keyboard.notify = new_virtual_keyboard;
	wl_signal_add(&vkbd->events.new_virtual_keyboard, &server->new_virtual_keyboard);
	struct wlr_virtual_pointer_manager_v1 *vptr =
		wlr_virtual_pointer_manager_v1_create(server->display);
	server->new_virtual_pointer.notify = new_virtual_pointer;
	wl_signal_add(&vptr->events.new_virtual_pointer, &server->new_virtual_pointer);
	server->seat = wlr_seat_create(server->display, "seat0");
	server->request_cursor.notify = request_cursor;
	wl_signal_add(&server->seat->events.request_set_cursor, &server->request_cursor);
	server->request_set_selection.notify = request_set_selection;
	wl_signal_add(&server->seat->events.request_set_selection, &server->request_set_selection);
	server->request_set_primary_selection.notify = request_set_primary_selection;
	wl_signal_add(&server->seat->events.request_set_primary_selection,
		&server->request_set_primary_selection);
}
