/*
 * layer.c: wlr-layer-shell, which is how the Quickshell side of Ultimit puts
 * the wallpaper, the icon rail, the clock, the ticker and notifications on
 * screen. Exclusive zones shrink the area windows are placed and maximized
 * into.
 */

#include <stdlib.h>
#include <string.h>
#include "server.h"

static enum ul_layer scene_layer_for(enum zwlr_layer_shell_v1_layer layer) {
	switch (layer) {
	case ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND:
		return UL_LAYER_BG;
	case ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM:
		return UL_LAYER_BOTTOM;
	case ZWLR_LAYER_SHELL_V1_LAYER_TOP:
		return UL_LAYER_TOP;
	case ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY:
	default:
		return UL_LAYER_OVERLAY;
	}
}

static void focus_exclusive(struct ul_server *server) {
	/* The topmost mapped surface asking for exclusive keyboard focus wins. */
	static const enum zwlr_layer_shell_v1_layer order[] = {
		ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, ZWLR_LAYER_SHELL_V1_LAYER_TOP,
	};
	struct ul_output *output;
	for (size_t i = 0; i < 2; i++) {
		wl_list_for_each(output, &server->outputs, link) {
			struct ul_layer_surface *l;
			wl_list_for_each_reverse(l, &output->layer_surfaces[order[i]], link) {
				if (l->mapped && l->layer_surface->current.keyboard_interactive ==
						ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE) {
					input_focus_layer(server, l->layer_surface);
					return;
				}
			}
		}
	}
	if (server->focused_layer &&
			server->focused_layer->current.keyboard_interactive ==
			ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE) {
		/* It went away or gave up exclusivity: hand focus back to windows. */
		input_focus_layer(server, NULL);
	}
}

void layer_arrange(struct ul_output *output) {
	struct wlr_box full = output->full_area;
	struct wlr_box usable = full;

	static const enum zwlr_layer_shell_v1_layer order[] = {
		ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, ZWLR_LAYER_SHELL_V1_LAYER_TOP,
		ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM, ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND,
	};
	/* Surfaces that reserve space (panels, the on-screen keyboard) first, so
	 * the rest fit in what is left whatever order they were mapped in. */
	for (int pass = 0; pass < 2; pass++)
	for (size_t i = 0; i < 4; i++) {
		struct ul_layer_surface *l;
		wl_list_for_each(l, &output->layer_surfaces[order[i]], link) {
			if (!l->layer_surface->initialized ||
					(l->layer_surface->current.exclusive_zone > 0) != (pass == 0)) {
				continue;
			}
			wlr_scene_layer_surface_v1_configure(l->scene, &full, &usable);
			wlr_scene_node_set_position(&l->popups->node,
				l->scene->tree->node.x, l->scene->tree->node.y);
		}
	}

	bool changed = memcmp(&usable, &output->usable_area, sizeof(usable)) != 0;
	output->usable_area = usable;
	if (changed && !output->server->relayout) {
		/* Re-fit maximized and snapped windows on this output to the new free area. */
		struct ul_view *view;
		wl_list_for_each(view, &output->server->views, link) {
			if ((view->maximized || view->snapped) && output_for_view(view) == output) {
				view_refit(view);
			}
		}
	}
	focus_exclusive(output->server);
}

struct wlr_scene_tree *layer_popup_parent(struct wlr_layer_surface_v1 *layer_surface,
		int *out_x, int *out_y, struct ul_output **out_output) {
	struct ul_layer_surface *l = layer_surface->data;
	if (!l) {
		return NULL;
	}
	if (out_x) *out_x = l->scene->tree->node.x;
	if (out_y) *out_y = l->scene->tree->node.y;
	if (out_output) *out_output = l->output;
	return l->popups;
}

/* The wallpaper and desktop widgets (background and bottom layers) are what the cached
 * glass blur shows, so the cache has to follow them. */
static bool under_glass(struct ul_layer_surface *l) {
	return l->layer_surface->current.layer <= ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM;
}

struct layer_blur {
	bool enabled, optimized;
};

static void set_layer_blur(struct wlr_scene_buffer *buffer, int sx, int sy, void *data) {
	struct layer_blur *b = data;
	if (wlr_scene_surface_try_from_buffer(buffer)) {
		wlr_scene_buffer_set_backdrop_blur(buffer, b->enabled);
		wlr_scene_buffer_set_backdrop_blur_optimized(buffer, b->optimized);
	}
}

/* Glass behind the shell's own panels above the windows (menus, flyouts, launcher,
 * dialogs, the rail and ticker). SceneFX blurs only under pixels that aren't fully
 * transparent, so a panel's invisible click-catcher stays clear. Panels that reserve a
 * screen edge (rail, ticker) only ever have the wallpaper under them and use the cheap
 * cached blur; the rest float over windows and blur what is really there. Other clients'
 * layer surfaces are left alone. */
static void layer_update_blur(struct ul_layer_surface *l) {
	const char *ns = l->layer_surface->namespace;
	struct layer_blur b = {
		.enabled = !under_glass(l) && ns && strncmp(ns, "ultimit-", 8) == 0,
		.optimized = l->layer_surface->current.exclusive_zone > 0,
	};
	wlr_scene_node_for_each_buffer(&l->scene->tree->node, set_layer_blur, &b);
}

static void layer_map(struct wl_listener *listener, void *data) {
	struct ul_layer_surface *l = wl_container_of(listener, l, map);
	l->mapped = true;
	if (under_glass(l)) {
		output_refresh_blur(l->output, true);
	}
	layer_arrange(l->output);
	if (l->layer_surface->current.keyboard_interactive ==
			ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND &&
			l->layer_surface->current.layer >= ZWLR_LAYER_SHELL_V1_LAYER_TOP) {
		input_focus_layer(l->server, l->layer_surface);
	}
	input_update_pointer_focus(l->server, 0);
}

static void layer_unmap(struct wl_listener *listener, void *data) {
	struct ul_layer_surface *l = wl_container_of(listener, l, unmap);
	l->mapped = false;
	if (l->server->focused_layer == l->layer_surface) {
		input_focus_layer(l->server, NULL);
	}
	if (l->output) {
		if (under_glass(l)) {
			output_refresh_blur(l->output, true);
		}
		layer_arrange(l->output);
	}
	input_update_pointer_focus(l->server, 0);
}

static void layer_commit(struct wl_listener *listener, void *data) {
	struct ul_layer_surface *l = wl_container_of(listener, l, commit);
	struct wlr_layer_surface_v1 *ls = l->layer_surface;
	if (!l->output) {
		return;
	}
	if (ls->current.committed & WLR_LAYER_SURFACE_V1_STATE_LAYER) {
		/* The client moved itself to a different layer. */
		enum ul_layer target = scene_layer_for(ls->current.layer);
		wlr_scene_node_reparent(&l->scene->tree->node, l->server->layers[target]);
		wl_list_remove(&l->link);
		wl_list_insert(&l->output->layer_surfaces[ls->current.layer], &l->link);
	}
	if (ls->initial_commit || ls->current.committed) {
		layer_arrange(l->output);
	}
	if (!l->mapped) {
		return;
	}
	if (under_glass(l)) {
		/* A new wallpaper frame: refresh this screen's glass (rate-limited). */
		output_refresh_blur(l->output, false);
	}
	layer_update_blur(l);
}

static void layer_destroy(struct wl_listener *listener, void *data) {
	struct ul_layer_surface *l = wl_container_of(listener, l, destroy);
	wl_list_remove(&l->link);
	wl_list_remove(&l->map.link);
	wl_list_remove(&l->unmap.link);
	wl_list_remove(&l->commit.link);
	wl_list_remove(&l->destroy.link);
	if (l->server->focused_layer == l->layer_surface) {
		l->server->focused_layer = NULL;
	}
	wlr_scene_node_destroy(&l->popups->node);
	struct ul_output *output = l->output;
	l->layer_surface->data = NULL;
	free(l);
	if (output) {
		layer_arrange(output);
	}
}

static void new_layer_surface(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, new_layer_surface);
	struct wlr_layer_surface_v1 *ls = data;

	struct ul_output *output = NULL;
	if (ls->output) {
		output = ls->output->data;
	} else {
		output = output_at(server, server->cursor->x, server->cursor->y);
		if (!output && !wl_list_empty(&server->outputs)) {
			output = wl_container_of(server->outputs.next, output, link);
		}
		if (output) {
			ls->output = output->wlr_output;
		}
	}
	if (!output) {
		wlr_layer_surface_v1_destroy(ls);
		return;
	}

	struct ul_layer_surface *l = calloc(1, sizeof(*l));
	l->server = server;
	l->output = output;
	l->layer_surface = ls;
	ls->data = l;
	l->scene = wlr_scene_layer_surface_v1_create(
		server->layers[scene_layer_for(ls->pending.layer)], ls);
	enum ul_layer popup_layer = ls->pending.layer == ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY ?
		UL_LAYER_OVERLAY : UL_LAYER_TOP;
	l->popups = wlr_scene_tree_create(server->layers[popup_layer]);
	wl_list_insert(&output->layer_surfaces[ls->pending.layer], &l->link);

	l->map.notify = layer_map;
	wl_signal_add(&ls->surface->events.map, &l->map);
	l->unmap.notify = layer_unmap;
	wl_signal_add(&ls->surface->events.unmap, &l->unmap);
	l->commit.notify = layer_commit;
	wl_signal_add(&ls->surface->events.commit, &l->commit);
	l->destroy.notify = layer_destroy;
	wl_signal_add(&ls->events.destroy, &l->destroy);
}

void layer_init(struct ul_server *server) {
	server->layer_shell = wlr_layer_shell_v1_create(server->display, 4);
	server->new_layer_surface.notify = new_layer_surface;
	wl_signal_add(&server->layer_shell->events.new_surface, &server->new_layer_surface);
}
