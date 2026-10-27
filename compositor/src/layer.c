/*
 * layer.c: wlr-layer-shell, which is how the Quickshell side of Ultimit puts
 * the wallpaper, the icon rail, the clock, the ticker and notifications on
 * screen. Exclusive zones shrink the area windows are placed and maximized
 * into.
 */

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>
#include "server.h"
#include "theme.h"

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
	for (size_t i = 0; i < 4; i++) {
		struct ul_layer_surface *l;
		wl_list_for_each(l, &output->layer_surfaces[order[i]], link) {
			if (!l->layer_surface->initialized) {
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

/* panel_blur_exclude: is `ns` one of the listed namespaces (separated by commas or spaces)? */
static bool blur_excluded(struct ul_server *server, const char *ns) {
	const char *list = server->config.panel_blur_exclude;
	size_t len = strlen(ns);
	while (*list) {
		list += strspn(list, ", \t");
		size_t n = strcspn(list, ", \t");
		if (n == len && n > 0 && strncmp(list, ns, n) == 0) {
			return true;
		}
		list += n;
	}
	return false;
}

/* ---- panel shadows ---------------------------------------------------------
 * The shell's panels live inside full-screen transparent layer surfaces, so the compositor
 * cannot see their rectangles; a shadow drawn by the shell inside the surface would be
 * backdrop-blurred with the panel. Instead the shell reports each panel's rect over the control
 * socket (`panel-shadow`) and the compositor draws a scenefx shadow behind the surface, with the
 * panel punched out, like the window shadow. The rail and ticker (exclusive-zone surfaces) get
 * one from their own geometry. Alpha fades over the reported time on a timer that only runs while
 * something is fading, so an idle desktop costs nothing. */

#define PANEL_SHADOW_AUTO "-auto"

struct ul_panel_shadow {
	struct wl_list link;
	char id[48];
	struct wlr_scene_shadow *node;
	struct wlr_box rect;
	int elev;
	float a_from, a_to, a_cur;
	uint32_t t0, ms;
	bool dying;
	struct ul_layer_surface *l;
};

static struct wl_event_source *shadow_timer;
static int shadows_fading;

static uint32_t shadow_now(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* Black, per level: elev2 = blur 32 / .45 (sigma 24 = the window shadow), elev1 = blur 16 / .30. */
static void shadow_place(struct ul_panel_shadow *s) {
	float sigma = s->elev == 1 ? UL_SHADOW_SIGMA * 0.5f : UL_SHADOW_SIGMA;
	float peak = s->elev == 1 ? 0.30f : 0.45f;
	int yoff = s->elev == 1 ? 2 : 8;
	int sg = (int)sigma;
	float c[4] = { 0, 0, 0, peak * s->a_cur };
	wlr_scene_shadow_set_color(s->node, c);
	wlr_scene_shadow_set_blur_sigma(s->node, sigma);
	wlr_scene_shadow_set_size(s->node, s->rect.width + 2 * sg, s->rect.height + 2 * sg);
	wlr_scene_node_set_position(&s->node->node, s->rect.x - sg, s->rect.y - sg + yoff);
	wlr_scene_shadow_set_clipped_region(s->node, (struct clipped_region){
		.corner_radius = 0,
		.corners = CORNER_LOCATION_NONE,
		.area = { sg, sg - yoff, s->rect.width, s->rect.height },
	});
}

static bool shadow_wanted(struct ul_panel_shadow *s) {
	struct ul_layer_surface *l = s->l;
	return l->mapped && s->a_cur > 0.002f && s->rect.width > 0 && s->rect.height > 0 &&
		!(l->output && l->output->panel_blur_off) &&
		!blur_excluded(l->server, l->layer_surface->namespace ? l->layer_surface->namespace : "");
}

static void shadow_refresh(struct ul_panel_shadow *s) {
	bool on = shadow_wanted(s);
	wlr_scene_node_set_enabled(&s->node->node, on);
	if (on) {
		shadow_place(s);
	}
}

static void shadow_free(struct ul_panel_shadow *s) {
	if (s->a_from != s->a_to) {
		shadows_fading--;
	}
	wl_list_remove(&s->link);
	wlr_scene_node_destroy(&s->node->node);
	free(s);
}

static int shadow_tick(void *data) {
	struct ul_server *server = data;
	uint32_t now = shadow_now();
	struct ul_output *output;
	wl_list_for_each(output, &server->outputs, link) {
		for (int i = 0; i < 4; i++) {
			struct ul_layer_surface *l;
			wl_list_for_each(l, &output->layer_surfaces[i], link) {
				struct ul_panel_shadow *s, *tmp;
				wl_list_for_each_safe(s, tmp, &l->shadows, link) {
					if (s->a_from == s->a_to) {
						continue;
					}
					double t = s->ms ? (double)(now - s->t0) / s->ms : 1;
					if (t >= 1) {
						s->a_cur = s->a_from = s->a_to;
						shadows_fading--;
						if (s->dying) {
							shadow_free(s);
							continue;
						}
					} else {
						double u = 1 - t;
						s->a_cur = s->a_from + (s->a_to - s->a_from) * (1 - u * u * u);
					}
					shadow_refresh(s);
				}
			}
		}
	}
	if (shadows_fading > 0) {
		wl_event_source_timer_update(shadow_timer, 16);
	}
	return 0;
}

static struct ul_panel_shadow *shadow_get(struct ul_layer_surface *l, const char *id, bool create) {
	struct ul_panel_shadow *s;
	wl_list_for_each(s, &l->shadows, link) {
		if (strcmp(s->id, id) == 0) {
			return s;
		}
	}
	if (!create) {
		return NULL;
	}
	s = calloc(1, sizeof(*s));
	snprintf(s->id, sizeof(s->id), "%s", id);
	s->l = l;
	float c[4] = { 0, 0, 0, 0 };
	s->node = wlr_scene_shadow_create(l->scene->tree, 1, 1, 0, UL_SHADOW_SIGMA, c);
	wlr_scene_node_lower_to_bottom(&s->node->node);
	wlr_scene_node_set_enabled(&s->node->node, false);
	wl_list_insert(&l->shadows, &s->link);
	return s;
}

static void shadow_set(struct ul_layer_surface *l, const char *id, struct wlr_box rect,
		int elev, float alpha, int ms) {
	struct ul_panel_shadow *s = shadow_get(l, id, elev > 0);
	if (!s) {
		return;
	}
	if (elev <= 0) {
		/* remove: fade out, then free */
		s->dying = true;
		alpha = 0;
	} else {
		s->rect = rect;
		s->elev = elev;
		s->dying = false;
	}
	if (s->a_from != s->a_to) {
		shadows_fading--;
	}
	if (ms <= 0 || !anim_motion() || alpha == s->a_cur) {
		s->a_cur = s->a_from = s->a_to = alpha;
		if (s->dying) {
			shadow_free(s);
			return;
		}
		shadow_refresh(s);
		return;
	}
	s->a_from = s->a_cur;
	s->a_to = alpha;
	s->t0 = shadow_now();
	s->ms = ms;
	shadows_fading++;
	shadow_refresh(s);
	if (!shadow_timer) {
		shadow_timer = wl_event_loop_add_timer(wl_display_get_event_loop(l->server->display),
			shadow_tick, l->server);
	}
	wl_event_source_timer_update(shadow_timer, 1);
}

/* The shell's report: `id` names a panel inside the surface (`ns` on `output`, "-" = any). */
bool layer_panel_shadow(struct ul_server *server, const char *ns, const char *output,
		const char *id, struct wlr_box rect, int elev, float alpha, int ms) {
	bool hit = false;
	struct ul_output *out;
	wl_list_for_each(out, &server->outputs, link) {
		if (strcmp(output, "-") != 0 && strcmp(out->wlr_output->name, output) != 0) {
			continue;
		}
		for (int i = 0; i < 4; i++) {
			struct ul_layer_surface *l;
			wl_list_for_each(l, &out->layer_surfaces[i], link) {
				if (l->layer_surface->namespace && strcmp(l->layer_surface->namespace, ns) == 0) {
					shadow_set(l, id, rect, elev, alpha, ms);
					hit = true;
				}
			}
		}
	}
	return hit;
}

/* Chrome that reserves a screen edge (rail, ticker): a level-1 shadow from the surface itself. */
static void shadow_auto(struct ul_layer_surface *l) {
	struct wlr_layer_surface_v1 *ls = l->layer_surface;
	if (!ls->namespace || strncmp(ls->namespace, "ultimit-", 8) != 0 ||
			ls->current.exclusive_zone <= 0 || !ls->surface->mapped) {
		return;
	}
	struct wlr_box r = { 0, 0, ls->current.actual_width, ls->current.actual_height };
	shadow_set(l, PANEL_SHADOW_AUTO, r, 1, 1.0f, 0);
}

static void shadows_update_layer(struct ul_layer_surface *l) {
	struct ul_panel_shadow *s;
	wl_list_for_each(s, &l->shadows, link) {
		shadow_refresh(s);
	}
}

/* The layer surface is gone and its scene tree (the shadow nodes with it) is already destroyed. */
static void shadows_free_layer(struct ul_layer_surface *l) {
	struct ul_panel_shadow *s, *tmp;
	wl_list_for_each_safe(s, tmp, &l->shadows, link) {
		if (s->a_from != s->a_to) {
			shadows_fading--;
		}
		wl_list_remove(&s->link);
		free(s);
	}
}

/* Glass behind the shell's own panels above the windows (menus, flyouts, launcher,
 * dialogs, the rail and ticker, toasts, OSD). SceneFX blurs only under pixels that aren't
 * fully transparent, so a panel's invisible click-catcher stays clear. Panels that reserve a
 * screen edge (rail, ticker) only ever have the wallpaper under them and use the cheap
 * cached blur; the rest float over windows and blur what is really there. Left out: other
 * clients' layer surfaces, the full-screen dimming scrims ([effects] panel_blur_exclude:
 * their translucent black would blur the whole screen), and any screen showing a
 * fullscreen window, so a toast or the volume OSD over a game costs no blur pass. */
static void layer_update_blur(struct ul_layer_surface *l) {
	const char *ns = l->layer_surface->namespace;
	struct ul_server *server = l->server;
	struct layer_blur b = {
		.enabled = server->config.panel_blur && !under_glass(l) &&
			!(l->output && l->output->panel_blur_off) &&
			ns && strncmp(ns, "ultimit-", 8) == 0 && !blur_excluded(server, ns),
		.optimized = l->layer_surface->current.exclusive_zone > 0,
	};
	wlr_scene_node_for_each_buffer(&l->scene->tree->node, set_layer_blur, &b);
}

/* Re-decide the glass of a screen's panels (fullscreen window came or went, config reload). */
void layer_update_output_blur(struct ul_output *output) {
	static const enum zwlr_layer_shell_v1_layer layers[] = {
		ZWLR_LAYER_SHELL_V1_LAYER_TOP, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY,
	};
	for (size_t i = 0; i < 2; i++) {
		struct ul_layer_surface *l;
		wl_list_for_each(l, &output->layer_surfaces[layers[i]], link) {
			if (l->mapped) {
				layer_update_blur(l);
				shadows_update_layer(l);
			}
		}
	}
}

void layer_update_all_blur(struct ul_server *server) {
	struct ul_output *output;
	wl_list_for_each(output, &server->outputs, link) {
		layer_update_output_blur(output);
	}
}

static void layer_map(struct wl_listener *listener, void *data) {
	struct ul_layer_surface *l = wl_container_of(listener, l, map);
	l->mapped = true;
	shadows_update_layer(l);
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
	shadows_update_layer(l);
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
	shadow_auto(l);
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
	shadows_free_layer(l);
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
	wl_list_init(&l->shadows);
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
