/*
 * xdg.c: native Wayland windows (xdg-shell), their popups, and the
 * xdg-decoration negotiation that decides who draws the titlebar.
 */

#include <stdlib.h>
#include "server.h"

static struct ul_view *view_from_xdg_surface(struct wlr_xdg_surface *xdg_surface) {
	if (!xdg_surface || xdg_surface->role != WLR_XDG_SURFACE_ROLE_TOPLEVEL ||
			!xdg_surface->data) {
		return NULL;
	}
	struct wlr_scene_tree *content = xdg_surface->data;
	return view_from_node(&content->node);
}

/* ---- toplevels ----------------------------------------------------------- */

static void xdg_map(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, map);
	struct wlr_box geo = view->xdg_toplevel->base->geometry;
	view->width = geo.width;
	view->height = geo.height;
	view_map(view);
}

static void xdg_unmap(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, unmap);
	view_unmap(view);
}

static void xdg_commit(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, commit);
	struct wlr_xdg_toplevel *toplevel = view->xdg_toplevel;

	if (toplevel->base->initial_commit) {
		/* Ask for server-side decorations when the client supports the
		 * protocol; let it pick its own size. */
		if (view->xdg_decoration) {
			wlr_xdg_toplevel_decoration_v1_set_mode(view->xdg_decoration,
				WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
		}
		wlr_xdg_toplevel_set_wm_capabilities(toplevel,
			WLR_XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE |
			WLR_XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN |
			WLR_XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE);
		wlr_xdg_toplevel_set_size(toplevel, 0, 0);
		return;
	}
	if (!view->mapped) {
		return;
	}
	struct wlr_box geo = toplevel->base->geometry;
	view_update_size(view, geo.width, geo.height);
}

static void xdg_destroy(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, destroy);
	wl_list_remove(&view->map.link);
	wl_list_remove(&view->unmap.link);
	wl_list_remove(&view->commit.link);
	wl_list_remove(&view->destroy.link);
	wl_list_remove(&view->request_move.link);
	wl_list_remove(&view->request_resize.link);
	wl_list_remove(&view->request_maximize.link);
	wl_list_remove(&view->request_fullscreen.link);
	wl_list_remove(&view->request_minimize.link);
	wl_list_remove(&view->set_title.link);
	wl_list_remove(&view->set_app_id.link);
	view_destroy(view);
}

static void xdg_request_move(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, request_move);
	view_begin_interactive(view, UL_CURSOR_MOVE, 0);
}

static void xdg_request_resize(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, request_resize);
	struct wlr_xdg_toplevel_resize_event *event = data;
	view_begin_interactive(view, UL_CURSOR_RESIZE, event->edges);
}

static void xdg_request_maximize(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, request_maximize);
	if (!view->mapped) {
		if (view->xdg_toplevel->base->initialized) {
			wlr_xdg_surface_schedule_configure(view->xdg_toplevel->base);
		}
		return;
	}
	view_set_maximized(view, view->xdg_toplevel->requested.maximized);
}

static void xdg_request_fullscreen(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, request_fullscreen);
	if (!view->mapped) {
		if (view->xdg_toplevel->base->initialized) {
			wlr_xdg_surface_schedule_configure(view->xdg_toplevel->base);
		}
		return;
	}
	view_set_fullscreen(view, view->xdg_toplevel->requested.fullscreen);
}

static void xdg_request_minimize(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, request_minimize);
	if (view->mapped) {
		view_set_minimized(view, true);
	}
}

static void xdg_set_title(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, set_title);
	view_update_title(view);
}

static void xdg_set_app_id(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, set_app_id);
	view_update_title(view);
}

static void new_xdg_toplevel(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, new_xdg_toplevel);
	struct wlr_xdg_toplevel *toplevel = data;

	struct ul_view *view = calloc(1, sizeof(*view));
	view->server = server;
	view->type = UL_VIEW_XDG;
	view->xdg_toplevel = toplevel;
	wl_list_init(&view->link);

	view->tree = wlr_scene_tree_create(server->layers[UL_LAYER_VIEWS]);
	view->tree->node.data = view;
	wlr_scene_node_set_enabled(&view->tree->node, false);
	decoration_create(view);
	view->content = wlr_scene_xdg_surface_create(view->tree, toplevel->base);
	toplevel->base->data = view->content;

	view->map.notify = xdg_map;
	wl_signal_add(&toplevel->base->surface->events.map, &view->map);
	view->unmap.notify = xdg_unmap;
	wl_signal_add(&toplevel->base->surface->events.unmap, &view->unmap);
	view->commit.notify = xdg_commit;
	wl_signal_add(&toplevel->base->surface->events.commit, &view->commit);
	view->destroy.notify = xdg_destroy;
	wl_signal_add(&toplevel->events.destroy, &view->destroy);
	view->request_move.notify = xdg_request_move;
	wl_signal_add(&toplevel->events.request_move, &view->request_move);
	view->request_resize.notify = xdg_request_resize;
	wl_signal_add(&toplevel->events.request_resize, &view->request_resize);
	view->request_maximize.notify = xdg_request_maximize;
	wl_signal_add(&toplevel->events.request_maximize, &view->request_maximize);
	view->request_fullscreen.notify = xdg_request_fullscreen;
	wl_signal_add(&toplevel->events.request_fullscreen, &view->request_fullscreen);
	view->request_minimize.notify = xdg_request_minimize;
	wl_signal_add(&toplevel->events.request_minimize, &view->request_minimize);
	view->set_title.notify = xdg_set_title;
	wl_signal_add(&toplevel->events.set_title, &view->set_title);
	view->set_app_id.notify = xdg_set_app_id;
	wl_signal_add(&toplevel->events.set_app_id, &view->set_app_id);
}

/* ---- popups -------------------------------------------------------------- */

struct ul_popup {
	struct wlr_xdg_popup *xdg_popup;
	struct wl_listener commit;
	struct wl_listener destroy;
};

/* Keeps menus on screen: the box is the output, expressed relative to the
 * root (toplevel or layer surface) the popup chain hangs off. */
static void popup_unconstrain(struct ul_popup *popup) {
	struct wlr_xdg_popup *xdg_popup = popup->xdg_popup;
	struct wlr_surface *parent = xdg_popup->parent;
	struct wlr_xdg_surface *parent_xdg;
	while ((parent_xdg = wlr_xdg_surface_try_from_wlr_surface(parent)) &&
			parent_xdg->role == WLR_XDG_SURFACE_ROLE_POPUP) {
		parent = parent_xdg->popup->parent;
	}

	struct ul_view *view = view_from_xdg_surface(parent_xdg);
	if (view) {
		struct ul_output *output = output_for_view(view);
		if (!output) {
			return;
		}
		struct wlr_box geo = view_geometry_offset(view);
		struct wlr_box box = {
			.x = output->full_area.x - view->x + geo.x,
			.y = output->full_area.y - view->y + geo.y,
			.width = output->full_area.width,
			.height = output->full_area.height,
		};
		wlr_xdg_popup_unconstrain_from_box(xdg_popup, &box);
		return;
	}

	struct wlr_layer_surface_v1 *layer = wlr_layer_surface_v1_try_from_wlr_surface(parent);
	if (layer) {
		int lx, ly;
		struct ul_output *output = NULL;
		layer_popup_parent(layer, &lx, &ly, &output);
		if (!output) {
			return;
		}
		struct wlr_box box = {
			.x = output->full_area.x - lx,
			.y = output->full_area.y - ly,
			.width = output->full_area.width,
			.height = output->full_area.height,
		};
		wlr_xdg_popup_unconstrain_from_box(xdg_popup, &box);
	}
}

static void popup_commit(struct wl_listener *listener, void *data) {
	struct ul_popup *popup = wl_container_of(listener, popup, commit);
	if (popup->xdg_popup->base->initial_commit) {
		popup_unconstrain(popup);
		wlr_xdg_surface_schedule_configure(popup->xdg_popup->base);
	}
}

static void popup_destroy(struct wl_listener *listener, void *data) {
	struct ul_popup *popup = wl_container_of(listener, popup, destroy);
	wl_list_remove(&popup->commit.link);
	wl_list_remove(&popup->destroy.link);
	free(popup);
}

static void new_xdg_popup(struct wl_listener *listener, void *data) {
	struct wlr_xdg_popup *xdg_popup = data;

	struct wlr_scene_tree *parent_tree = NULL;
	struct wlr_xdg_surface *parent = wlr_xdg_surface_try_from_wlr_surface(xdg_popup->parent);
	if (parent) {
		parent_tree = parent->data;
	} else {
		struct wlr_layer_surface_v1 *layer =
			wlr_layer_surface_v1_try_from_wlr_surface(xdg_popup->parent);
		if (layer) {
			parent_tree = layer_popup_parent(layer, NULL, NULL, NULL);
		}
	}
	if (!parent_tree) {
		/* Parent we don't manage (e.g. a lock surface); nothing to anchor to. */
		return;
	}

	struct ul_popup *popup = calloc(1, sizeof(*popup));
	popup->xdg_popup = xdg_popup;
	xdg_popup->base->data = wlr_scene_xdg_surface_create(parent_tree, xdg_popup->base);

	popup->commit.notify = popup_commit;
	wl_signal_add(&xdg_popup->base->surface->events.commit, &popup->commit);
	popup->destroy.notify = popup_destroy;
	wl_signal_add(&xdg_popup->events.destroy, &popup->destroy);
}

/* ---- xdg-decoration ------------------------------------------------------ */

static void decoration_request_mode(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, decoration_request_mode);
	/* We always draw the Ultimit titlebar when the client lets us. */
	if (view->xdg_toplevel->base->initialized) {
		wlr_xdg_toplevel_decoration_v1_set_mode(view->xdg_decoration,
			WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
	}
	view_set_ssd(view, true);
}

static void decoration_destroy(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, decoration_destroy);
	wl_list_remove(&view->decoration_request_mode.link);
	wl_list_remove(&view->decoration_destroy.link);
	view->xdg_decoration = NULL;
	view_set_ssd(view, false);
}

static void new_decoration(struct wl_listener *listener, void *data) {
	struct wlr_xdg_toplevel_decoration_v1 *decoration = data;
	struct ul_view *view = view_from_xdg_surface(decoration->toplevel->base);
	if (!view) {
		return;
	}
	view->xdg_decoration = decoration;
	view->decoration_request_mode.notify = decoration_request_mode;
	wl_signal_add(&decoration->events.request_mode, &view->decoration_request_mode);
	view->decoration_destroy.notify = decoration_destroy;
	wl_signal_add(&decoration->events.destroy, &view->decoration_destroy);
	view_set_ssd(view, true);
	if (decoration->toplevel->base->initialized) {
		wlr_xdg_toplevel_decoration_v1_set_mode(decoration,
			WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
	}
}

/* ---- xdg-activation (apps asking to be raised, e.g. "open in browser") --- */

static void request_activate(struct wl_listener *listener, void *data) {
	struct wlr_xdg_activation_v1_request_activate_event *event = data;
	struct wlr_xdg_surface *xdg = wlr_xdg_surface_try_from_wlr_surface(event->surface);
	struct ul_view *view = view_from_xdg_surface(xdg);
	if (view && view->mapped) {
		view_focus(view);
	}
}

void xdg_init(struct ul_server *server) {
	server->xdg_shell = wlr_xdg_shell_create(server->display, 6);
	server->new_xdg_toplevel.notify = new_xdg_toplevel;
	wl_signal_add(&server->xdg_shell->events.new_toplevel, &server->new_xdg_toplevel);
	server->new_xdg_popup.notify = new_xdg_popup;
	wl_signal_add(&server->xdg_shell->events.new_popup, &server->new_xdg_popup);

	server->decoration_manager = wlr_xdg_decoration_manager_v1_create(server->display);
	server->new_decoration.notify = new_decoration;
	wl_signal_add(&server->decoration_manager->events.new_toplevel_decoration,
		&server->new_decoration);

	server->activation = wlr_xdg_activation_v1_create(server->display);
	server->request_activate.notify = request_activate;
	wl_signal_add(&server->activation->events.request_activate, &server->request_activate);
}
