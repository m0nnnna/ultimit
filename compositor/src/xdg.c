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

static void apply_decoration_mode(struct ul_view *view);

/* ---- toplevels ----------------------------------------------------------- */

static void xdg_map(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, map);
	if (!view->xdg_decoration &&
			xdg_kde_wants_ssd(view->server, view->xdg_toplevel->base->surface)) {
		view->ssd = true;
	}
	struct wlr_box geo = view->xdg_toplevel->base->geometry;
	view->width = geo.width;
	view->height = geo.height;
	view->geo_x = geo.x;
	view->geo_y = geo.y;
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
			apply_decoration_mode(view);
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
	capture_view_commit(view);
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
	view->id = ++server->next_view_id;
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
	bool attached;
	struct wl_listener commit;
	struct wl_listener reposition;
	struct wl_listener destroy;
};

/* Keeps menus on screen: the box is the output, expressed relative to the
 * root (toplevel or layer surface) the popup chain hangs off. */
static void popup_unconstrain(struct ul_popup *popup) {
	struct wlr_xdg_popup *xdg_popup = popup->xdg_popup;
	struct wlr_surface *parent = xdg_popup->parent;
	struct wlr_xdg_surface *parent_xdg = NULL;
	while (parent && (parent_xdg = wlr_xdg_surface_try_from_wlr_surface(parent)) &&
			parent_xdg->role == WLR_XDG_SURFACE_ROLE_POPUP) {
		parent = parent_xdg->popup->parent;
	}
	if (!parent) {
		return;
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

/* Put the popup into the scene under its parent. Layer-shell popups are
 * created without a parent (zwlr_layer_surface_v1.get_popup assigns it
 * later), so this can only happen once the parent is known. Returns false
 * if there is nothing we manage to anchor it to. */
static bool popup_attach(struct ul_popup *popup) {
	struct wlr_xdg_popup *xdg_popup = popup->xdg_popup;
	if (popup->attached) {
		return true;
	}
	if (!xdg_popup->parent) {
		return false;
	}
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
		/* A parent we don't manage (e.g. a lock surface). */
		return false;
	}
	xdg_popup->base->data = wlr_scene_xdg_surface_create(parent_tree, xdg_popup->base);
	popup->attached = true;
	return true;
}

static void popup_commit(struct wl_listener *listener, void *data) {
	struct ul_popup *popup = wl_container_of(listener, popup, commit);
	if (popup->xdg_popup->base->initial_commit) {
		popup_attach(popup);
		popup_unconstrain(popup);
		wlr_xdg_surface_schedule_configure(popup->xdg_popup->base);
	}
}

/* GTK4 menus ask to be re-placed right after opening; keep them on screen
 * then too. */
static void popup_reposition(struct wl_listener *listener, void *data) {
	struct ul_popup *popup = wl_container_of(listener, popup, reposition);
	popup_unconstrain(popup);
}

static void popup_destroy(struct wl_listener *listener, void *data) {
	struct ul_popup *popup = wl_container_of(listener, popup, destroy);
	wl_list_remove(&popup->commit.link);
	wl_list_remove(&popup->reposition.link);
	wl_list_remove(&popup->destroy.link);
	free(popup);
}

static void new_xdg_popup(struct wl_listener *listener, void *data) {
	struct wlr_xdg_popup *xdg_popup = data;

	struct ul_popup *popup = calloc(1, sizeof(*popup));
	popup->xdg_popup = xdg_popup;
	/* Parent may not be set yet (layer-shell popups); see popup_attach. */
	popup_attach(popup);

	popup->commit.notify = popup_commit;
	wl_signal_add(&xdg_popup->base->surface->events.commit, &popup->commit);
	popup->reposition.notify = popup_reposition;
	wl_signal_add(&xdg_popup->events.reposition, &popup->reposition);
	popup->destroy.notify = popup_destroy;
	wl_signal_add(&xdg_popup->events.destroy, &popup->destroy);
}

/* ---- xdg-decoration ------------------------------------------------------ */

/* We draw the Ultimit titlebar unless the client explicitly asks to draw its
 * own (Chromium's tab strip, for example). Overriding that request just gets
 * two titlebars. */
static enum wlr_xdg_toplevel_decoration_v1_mode decoration_mode_for(
		struct wlr_xdg_toplevel_decoration_v1 *decoration) {
	return decoration->requested_mode == WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE ?
		WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE :
		WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE;
}

static void apply_decoration_mode(struct ul_view *view) {
	enum wlr_xdg_toplevel_decoration_v1_mode mode = decoration_mode_for(view->xdg_decoration);
	if (view->xdg_toplevel->base->initialized) {
		wlr_xdg_toplevel_decoration_v1_set_mode(view->xdg_decoration, mode);
	}
	view_set_ssd(view, mode == WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
}

static void decoration_request_mode(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, decoration_request_mode);
	apply_decoration_mode(view);
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
	apply_decoration_mode(view);
}

/* ---- KDE server-decoration ---------------------------------------------- */

struct ul_kde_decoration {
	struct wl_list link;
	struct ul_server *server;
	struct wlr_server_decoration *decoration;
	struct wl_listener mode;
	struct wl_listener destroy;
};

bool xdg_kde_wants_ssd(struct ul_server *server, struct wlr_surface *surface) {
	struct ul_kde_decoration *d;
	wl_list_for_each(d, &server->kde_decorations, link) {
		if (d->decoration->surface == surface) {
			return d->decoration->mode == WLR_SERVER_DECORATION_MANAGER_MODE_SERVER;
		}
	}
	return false;
}

static void kde_decoration_apply(struct ul_kde_decoration *d) {
	struct wlr_xdg_surface *xdg = wlr_xdg_surface_try_from_wlr_surface(d->decoration->surface);
	struct ul_view *view = view_from_xdg_surface(xdg);
	if (view && !view->xdg_decoration) {
		view_set_ssd(view, d->decoration->mode == WLR_SERVER_DECORATION_MANAGER_MODE_SERVER);
	}
}

static void kde_decoration_mode(struct wl_listener *listener, void *data) {
	struct ul_kde_decoration *d = wl_container_of(listener, d, mode);
	kde_decoration_apply(d);
}

static void kde_decoration_destroy(struct wl_listener *listener, void *data) {
	struct ul_kde_decoration *d = wl_container_of(listener, d, destroy);
	wl_list_remove(&d->link);
	wl_list_remove(&d->mode.link);
	wl_list_remove(&d->destroy.link);
	free(d);
}

static void new_kde_decoration(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, new_kde_decoration);
	struct ul_kde_decoration *d = calloc(1, sizeof(*d));
	d->server = server;
	d->decoration = data;
	wl_list_insert(&server->kde_decorations, &d->link);
	d->mode.notify = kde_decoration_mode;
	wl_signal_add(&d->decoration->events.mode, &d->mode);
	d->destroy.notify = kde_decoration_destroy;
	wl_signal_add(&d->decoration->events.destroy, &d->destroy);
	kde_decoration_apply(d);
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

	wl_list_init(&server->kde_decorations);
	server->kde_decoration_manager = wlr_server_decoration_manager_create(server->display);
	wlr_server_decoration_manager_set_default_mode(server->kde_decoration_manager,
		WLR_SERVER_DECORATION_MANAGER_MODE_SERVER);
	server->new_kde_decoration.notify = new_kde_decoration;
	wl_signal_add(&server->kde_decoration_manager->events.new_decoration,
		&server->new_kde_decoration);

	server->activation = wlr_xdg_activation_v1_create(server->display);
	server->request_activate.notify = request_activate;
	wl_signal_add(&server->activation->events.request_activate, &server->request_activate);
}
