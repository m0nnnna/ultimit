/*
 * output.c: monitors. Each frame is built from the scene graph; when a
 * fullscreen game owns an output we turn on adaptive sync, and allow tearing
 * page flips if the game asked for them (wp_tearing_control).
 */

#include <math.h>
#include <stdlib.h>
#include <time.h>
#include "server.h"
#include "theme.h"

struct ul_output *output_at(struct ul_server *server, double lx, double ly) {
	struct wlr_output *wlr_output = wlr_output_layout_output_at(server->output_layout, lx, ly);
	return wlr_output ? wlr_output->data : NULL;
}

struct ul_output *output_for_view(struct ul_view *view) {
	double cx = view->x + view->width / 2.0;
	double cy = view->y + view->height / 2.0;
	struct ul_output *output = output_at(view->server, cx, cy);
	if (!output) {
		double nx, ny;
		wlr_output_layout_closest_point(view->server->output_layout, NULL, cx, cy, &nx, &ny);
		output = output_at(view->server, nx, ny);
	}
	return output;
}

/* "make|model|serial" from the EDID: how displays.conf recognises a monitor on any connector. */
void output_identity(struct wlr_output *wlr_output, char *buf, size_t len) {
	snprintf(buf, len, "%s|%s|%s", wlr_output->make ? wlr_output->make : "",
		wlr_output->model ? wlr_output->model : "", wlr_output->serial ? wlr_output->serial : "");
}

static bool in_layout(struct ul_output *output) {
	return (output->wlr_output->enabled || output->power_off) &&
		wlr_output_layout_get(output->server->output_layout, output->wlr_output) != NULL;
}

/* The main display: the one marked primary, else the first in the layout. */
struct ul_output *output_primary(struct ul_server *server) {
	struct ul_output *output, *first = NULL;
	wl_list_for_each_reverse(output, &server->outputs, link) {
		if (!in_layout(output)) continue;
		if (output->primary) return output;
		if (!first) first = output;
	}
	return first;
}

/* Call before changing the layout: remember where every output was. */
void output_remember_layout(struct ul_server *server) {
	server->relayout = true;
	struct ul_output *output;
	wl_list_for_each(output, &server->outputs, link) {
		output->prev_area = in_layout(output) ? output->full_area : (struct wlr_box){ 0 };
	}
}

/* After a layout change (monitors moved, resized, rotated, turned off or unplugged; `gone` is
 * one about to disappear): windows follow their monitor. Each window was on the output whose old
 * box held its centre; it moves by that output's offset and is kept inside the new box. Windows
 * of a monitor that is gone, and any that were off every screen, go to the main display.
 * Maximized, snapped and fullscreen windows are fitted again. */
void output_relocate_views(struct ul_server *server, struct ul_output *gone) {
	struct ul_output *primary = output_primary(server);
	if (primary == gone) {
		primary = NULL;
		struct ul_output *o;
		wl_list_for_each(o, &server->outputs, link) {
			if (o != gone && in_layout(o)) { primary = o; break; }
		}
	}
	server->relayout = false;   /* from here on, re-fitting below is wanted */
	/* No screen left to move to (all of them coming back from suspend, say): windows keep
	 * their place, which is theirs again when the monitors return. */
	if (!primary) return;
	struct ul_view *view;
	wl_list_for_each(view, &server->views, link) {
		if (!view->mapped && !view->minimized) continue;
		double cx = view->x + view->width / 2.0, cy = view->y + view->height / 2.0;
		/* Duplicated (mirrored) monitors overlap: then the window belongs to the main one. */
		struct ul_output *from = NULL, *o;
		wl_list_for_each(o, &server->outputs, link) {
			if (!wlr_box_empty(&o->prev_area) && wlr_box_contains_point(&o->prev_area, cx, cy) &&
					(!from || o == primary)) {
				from = o;
			}
		}
		struct ul_output *to = from && from != gone && in_layout(from) ? from : primary;
		struct wlr_box src = from ? from->prev_area : to->full_area, dst = to->full_area;
		if (to == from && memcmp(&src, &dst, sizeof(src)) == 0) continue;   /* didn't move */
		/* Same place relative to the monitor's top-left, then inside its free area. */
		view_set_position(view, dst.x + (view->x - src.x), dst.y + (view->y - src.y));
		if (view->fullscreen) {
			view_set_position(view, dst.x, dst.y);
			view_request_size(view, dst.width, dst.height);
		} else if (view->maximized || view->snapped) {
			view_refit(view);
		} else {
			view_clamp_into(view, to->usable_area);
		}
		if (view->snapped || view->maximized) {
			/* What Restore returns to moves along too. */
			view->saved.x = dst.x + (view->saved.x - src.x);
			view->saved.y = dst.y + (view->saved.y - src.y);
		}
	}
	server->relayout = false;
}

/* How often a screen's cached glass blur may be redrawn while its wallpaper is moving. The
 * moving shards run at up to 20 fps; following them at half that keeps the glass alive
 * without a full-screen redraw on every wallpaper frame. */
#define BLUR_REFRESH_MS 100

static int blur_refresh(void *data) {
	struct ul_output *output = data;
	output->blur_pending = false;
	wlr_scene_optimized_blur_mark_dirty(output->blur);
	return 0;
}

/* SceneFX draws an optimized blur node once and keeps it until it is marked dirty, which it
 * never does on its own when what lies under it changes. Without this a screen keeps the
 * glass it had when it came up: plain backdrop if the wallpaper wasn't drawn yet, which is
 * why some screens' windows looked frosted and others' flat. */
void output_refresh_blur(struct ul_output *output, bool now) {
	if (!output || !output->blur) {
		return;
	}
	if (now) {
		if (output->blur_pending) {
			wl_event_source_timer_update(output->blur_timer, 0);
			output->blur_pending = false;
		}
		wlr_scene_optimized_blur_mark_dirty(output->blur);
		return;
	}
	if (output->blur_pending) {
		return;
	}
	if (!output->blur_timer) {
		output->blur_timer = wl_event_loop_add_timer(
			wl_display_get_event_loop(output->server->display), blur_refresh, output);
	}
	output->blur_pending = true;
	wl_event_source_timer_update(output->blur_timer, BLUR_REFRESH_MS);
}

void server_update_backdrop(struct ul_server *server) {
	struct wlr_box box;
	wlr_output_layout_get_box(server->output_layout, NULL, &box);
	wlr_scene_node_set_position(&server->backdrop->node, box.x, box.y);
	wlr_scene_rect_set_size(server->backdrop, box.width, box.height);
	struct ul_output *output;
	wl_list_for_each(output, &server->outputs, link) {   /* each screen's own blur cache */
		if (!output->blur) continue;
		/* A screen that is off must not leave its node over another one's area. (Duplicated
		 * screens overlap, so one of them still blurs the slow way.) */
		wlr_scene_node_set_enabled(&output->blur->node, in_layout(output));
		wlr_scene_node_set_position(&output->blur->node, output->full_area.x, output->full_area.y);
		wlr_scene_optimized_blur_set_size(output->blur, output->full_area.width, output->full_area.height);
	}
	lock_arrange(server);
}

void output_arrange(struct ul_output *output) {
	wlr_output_layout_get_box(output->server->output_layout, output->wlr_output,
		&output->full_area);
	layer_arrange(output);

	struct ul_view *view;
	wl_list_for_each(view, &output->server->views, link) {
		if (output->server->relayout) break;   /* output_relocate_views takes care of them */
		if (view->fullscreen && output_for_view(view) == output) {
			view_set_position(view, output->full_area.x, output->full_area.y);
			view_request_size(view, output->full_area.width, output->full_area.height);
		}
	}
	server_update_backdrop(output->server);
}

static struct ul_view *fullscreen_view_on(struct ul_output *output) {
	struct ul_view *view;
	wl_list_for_each(view, &output->server->views, link) {
		if (view->mapped && view->fullscreen && !view->minimized &&
				output_for_view(view) == output) {
			return view;
		}
	}
	return NULL;
}

static void output_frame(struct wl_listener *listener, void *data) {
	struct ul_output *output = wl_container_of(listener, output, frame);
	struct wlr_output *wlr_output = output->wlr_output;
	struct wlr_scene_output *scene_output = output->scene_output;

	/* Window animations step here, right before the frame is built, so
	 * they move once per frame at this monitor's rate. */
	bool moving = anim_frame(output->server);
	struct ul_view *game = fullscreen_view_on(output);

	if (wlr_scene_output_needs_frame(scene_output)) {
		struct wlr_output_state state;
		wlr_output_state_init(&state);

		bool want_vrr = game != NULL || output->vrr_always;
		bool vrr_on = wlr_output->adaptive_sync_status == WLR_OUTPUT_ADAPTIVE_SYNC_ENABLED;
		bool vrr_change = wlr_output->adaptive_sync_supported && want_vrr != vrr_on;
		if (vrr_change) {
			wlr_output_state_set_adaptive_sync_enabled(&state, want_vrr);
		}

		if (wlr_scene_output_build_state(scene_output, &state, NULL)) {
			state.tearing_page_flip = game && view_wants_tearing(game);
			bool ok = wlr_output_commit_state(wlr_output, &state);
			if (!ok && (state.tearing_page_flip || vrr_change)) {
				/* Driver refused tearing or VRR; present normally. */
				state.tearing_page_flip = false;
				state.committed &= ~WLR_OUTPUT_STATE_ADAPTIVE_SYNC_ENABLED;
				wlr_output_commit_state(wlr_output, &state);
			}
		}
		wlr_output_state_finish(&state);
	}

	/* Subsurface and popup commits don't pass through the view's own commit
	 * handler; window capture notices them here. */
	capture_output_frame(output->server);

	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	wlr_scene_output_send_frame_done(scene_output, &now);

	/* Keep frames coming while something moves, also through steps that
	 * change no pixel (an ease flattening out). Not on a game's output:
	 * its frames are paced by the game. */
	if (moving && !game) {
		wlr_output_schedule_frame(wlr_output);
	}
}

/* The power key on phones: switch the panels off (and back on) without taking
 * them out of the layout, so windows stay where they are. */
void output_set_screen_off(struct ul_server *server, bool off) {
	server->screen_off = off;
	struct ul_output *output;
	wl_list_for_each(output, &server->outputs, link) {
		if (off ? !output->wlr_output->enabled : !output->power_off) {
			continue;
		}
		struct wlr_output_state state;
		wlr_output_state_init(&state);
		wlr_output_state_set_enabled(&state, !off);
		if (wlr_output_commit_state(output->wlr_output, &state)) {
			output->power_off = off;
		}
		wlr_output_state_finish(&state);
		if (!off) {
			wlr_output_schedule_frame(output->wlr_output);
		}
	}
}

static void output_request_state(struct wl_listener *listener, void *data) {
	/* The nested (Wayland/X11) backends ask for a new mode when the host
	 * window is resized. */
	struct ul_output *output = wl_container_of(listener, output, request_state);
	const struct wlr_output_event_request_state *event = data;
	wlr_output_commit_state(output->wlr_output, event->state);
	output_arrange(output);
}

static void output_destroy(struct wl_listener *listener, void *data) {
	struct ul_output *output = wl_container_of(listener, output, destroy);
	struct ul_server *server = output->server;
	/* Unplugged: its windows go to the main display (the layout still has it here). */
	output_remember_layout(server);
	wlr_output_layout_remove(server->output_layout, output->wlr_output);
	/* The scene output would otherwise live until after this signal (it's an addon), and
	 * windows moved below could "enter" the dying output at its stale position: that adds
	 * a bind listener nothing removes, and wlr_output_finish aborts. */
	wlr_scene_output_destroy(output->scene_output);
	output->scene_output = NULL;
	struct ul_output *other;
	wl_list_for_each(other, &server->outputs, link) {   /* auto-placed ones may have shifted */
		if (other != output && in_layout(other)) output_arrange(other);
	}
	output_relocate_views(server, output);
	output->prev_area = (struct wlr_box){ 0 };
	for (int i = 0; i < 4; i++) {
		struct ul_layer_surface *l, *tmp;
		wl_list_for_each_safe(l, tmp, &output->layer_surfaces[i], link) {
			l->output = NULL;
			wl_list_remove(&l->link);
			wl_list_init(&l->link);
			wlr_layer_surface_v1_destroy(l->layer_surface);
		}
	}
	wl_list_remove(&output->frame.link);
	wl_list_remove(&output->request_state.link);
	wl_list_remove(&output->destroy.link);
	wl_list_remove(&output->link);
	if (output->blur_timer) {
		wl_event_source_remove(output->blur_timer);
	}
	wlr_scene_node_destroy(&output->blur->node);
	output->wlr_output->data = NULL;
	free(output);
	server_update_backdrop(server);
}

static void new_output(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, new_output);
	struct wlr_output *wlr_output = data;

	wlr_output_init_render(wlr_output, server->allocator, server->renderer);

	/* The user's saved setup (Settings > Display), else the preferred mode:
	 * normally the native resolution at its highest refresh rate. */
	struct ul_output_conf conf;
	char id[256];
	output_identity(wlr_output, id, sizeof(id));
	bool have_conf = config_output_lookup(wlr_output->name, id, &conf);
	if (have_conf && !conf.enabled && wl_list_empty(&server->outputs)) {
		/* Never start with every screen off; the next one may never come. */
		wlr_log(WLR_INFO, "Output %s is disabled in displays.conf but is the only one; enabling",
			wlr_output->name);
		conf.enabled = true;
	}
	bool enabled = !have_conf || conf.enabled;

	struct wlr_output_state state;
	wlr_output_state_init(&state);
	wlr_output_state_set_enabled(&state, enabled);
	/* Default: the native (preferred) resolution at its highest refresh rate. Many high-refresh
	 * monitors mark their 60 Hz timing as preferred. */
	struct wlr_output_mode *mode = wlr_output_preferred_mode(wlr_output);
	if (mode) {
		struct wlr_output_mode *m;
		wl_list_for_each(m, &wlr_output->modes, link) {
			if (m->width == mode->width && m->height == mode->height && m->refresh > mode->refresh) {
				mode = m;
			}
		}
	}
	if (enabled && have_conf && conf.width > 0) {
		struct wlr_output_mode *m, *best = NULL;
		wl_list_for_each(m, &wlr_output->modes, link) {
			if (m->width != conf.width || m->height != conf.height) continue;
			if (conf.refresh_hz > 0) {
				if (fabs(m->refresh / 1000.0 - conf.refresh_hz) < 0.5 &&
						(!best || fabs(m->refresh / 1000.0 - conf.refresh_hz) <
						fabs(best->refresh / 1000.0 - conf.refresh_hz))) {
					best = m;
				}
			} else if (!best || m->refresh > best->refresh) {
				best = m;
			}
		}
		if (best) {
			mode = best;
		} else if (wl_list_empty(&wlr_output->modes)) {
			/* Nested/headless outputs have no mode list. */
			mode = NULL;
			wlr_output_state_set_custom_mode(&state, conf.width, conf.height,
				(int)(conf.refresh_hz * 1000));
		}
	}
	if (enabled && mode) {
		wlr_output_state_set_mode(&state, mode);
	}
	if (enabled && have_conf) {
		if (conf.scale > 0) wlr_output_state_set_scale(&state, conf.scale);
		wlr_output_state_set_transform(&state, conf.transform);
	}
	if (!wlr_output_commit_state(wlr_output, &state) && have_conf && enabled) {
		/* A saved mode the monitor no longer takes: fall back to defaults. */
		wlr_log(WLR_ERROR, "Output %s rejected displays.conf; using its preferred mode",
			wlr_output->name);
		wlr_output_state_finish(&state);
		wlr_output_state_init(&state);
		wlr_output_state_set_enabled(&state, true);
		if ((mode = wlr_output_preferred_mode(wlr_output))) {
			wlr_output_state_set_mode(&state, mode);
		}
		wlr_output_commit_state(wlr_output, &state);
	}
	wlr_output_state_finish(&state);

	struct ul_output *output = calloc(1, sizeof(*output));
	output->server = server;
	output->wlr_output = wlr_output;
	wlr_output->data = output;
	for (int i = 0; i < 4; i++) {
		wl_list_init(&output->layer_surfaces[i]);
	}

	output->frame.notify = output_frame;
	wl_signal_add(&wlr_output->events.frame, &output->frame);
	output->request_state.notify = output_request_state;
	wl_signal_add(&wlr_output->events.request_state, &output->request_state);
	output->destroy.notify = output_destroy;
	wl_signal_add(&wlr_output->events.destroy, &output->destroy);
	wl_list_insert(&server->outputs, &output->link);

	output->vrr_always = have_conf && conf.adaptive_sync;
	output->primary = have_conf && conf.primary;
	output->scene_output = wlr_scene_output_create(server->scene, wlr_output);
	output->blur = wlr_scene_optimized_blur_create(server->blur_layer, 0, 0);
	if (!enabled) {
		wlr_log(WLR_INFO, "Output %s: disabled (displays.conf)", wlr_output->name);
		return;
	}
	struct wlr_output_layout_output *layout_output = have_conf && conf.has_pos ?
		wlr_output_layout_add(server->output_layout, wlr_output, conf.x, conf.y) :
		wlr_output_layout_add_auto(server->output_layout, wlr_output);
	wlr_scene_output_layout_add_output(server->scene_layout, layout_output,
		output->scene_output);

	wlr_log(WLR_INFO, "Output %s: %dx%d @ %.2f Hz, adaptive sync %s",
		wlr_output->name, wlr_output->width, wlr_output->height,
		wlr_output->refresh / 1000.0,
		wlr_output->adaptive_sync_supported ? "supported" : "not supported");

	output_arrange(output);
}

/* ---- wlr-output-management ---------------------------------------------- */

/* Publish the current layout (modes, positions, scale...) to clients. */
static void update_output_manager(struct ul_server *server) {
	struct wlr_output_configuration_v1 *config = wlr_output_configuration_v1_create();
	struct ul_output *output;
	wl_list_for_each(output, &server->outputs, link) {
		struct wlr_output_configuration_head_v1 *head =
			wlr_output_configuration_head_v1_create(config, output->wlr_output);
		struct wlr_box box;
		wlr_output_layout_get_box(server->output_layout, output->wlr_output, &box);
		head->state.enabled = output->wlr_output->enabled && !wlr_box_empty(&box);
		head->state.x = box.x;
		head->state.y = box.y;
	}
	wlr_output_manager_v1_set_configuration(server->output_manager, config);
}

static void apply_output_config(struct ul_server *server,
		struct wlr_output_configuration_v1 *config, bool test_only) {
	size_t len = 0;
	struct wlr_backend_output_state *states =
		wlr_output_configuration_v1_build_state(config, &len);
	bool ok = states != NULL;
	if (ok) {
		ok = test_only ? wlr_backend_test(server->backend, states, len) :
			wlr_backend_commit(server->backend, states, len);
	}
	if (ok && !test_only) {
		output_remember_layout(server);
		struct wlr_output_configuration_head_v1 *head;
		wl_list_for_each(head, &config->heads, link) {
			struct wlr_output *wlr_output = head->state.output;
			struct ul_output *output = wlr_output->data;
			if (!output) continue;
			output->vrr_always = head->state.enabled && head->state.adaptive_sync_enabled;
			if (head->state.enabled) {
				struct wlr_output_layout_output *lo = wlr_output_layout_add(
					server->output_layout, wlr_output, head->state.x, head->state.y);
				wlr_scene_output_layout_add_output(server->scene_layout, lo,
					output->scene_output);
			} else {
				wlr_output_layout_remove(server->output_layout, wlr_output);
			}
		}
		wl_list_for_each(head, &config->heads, link) {
			struct ul_output *output = head->state.output->data;
			if (output && head->state.enabled) {
				output_arrange(output);
			}
		}
		output_relocate_views(server, NULL);
	}
	for (size_t i = 0; i < len; i++) {
		wlr_output_state_finish(&states[i].base);
	}
	free(states);
	if (ok) {
		wlr_output_configuration_v1_send_succeeded(config);
	} else {
		wlr_output_configuration_v1_send_failed(config);
	}
	wlr_output_configuration_v1_destroy(config);
	update_output_manager(server);
}

static void output_manager_apply(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, output_apply);
	apply_output_config(server, data, false);
}

static void output_manager_test(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, output_test);
	apply_output_config(server, data, true);
}

static void layout_change(struct wl_listener *listener, void *data) {
	struct ul_server *server = wl_container_of(listener, server, layout_change);
	update_output_manager(server);
	xwayland_sync_primary(server);
}

void output_finish(struct ul_server *server) {
	wl_list_remove(&server->output_apply.link);
	wl_list_remove(&server->output_test.link);
	wl_list_remove(&server->layout_change.link);
}

void output_init(struct ul_server *server) {
	wl_list_init(&server->outputs);
	server->output_layout = wlr_output_layout_create(server->display);
	server->output_manager = wlr_output_manager_v1_create(server->display);
	server->output_apply.notify = output_manager_apply;
	wl_signal_add(&server->output_manager->events.apply, &server->output_apply);
	server->output_test.notify = output_manager_test;
	wl_signal_add(&server->output_manager->events.test, &server->output_test);
	server->layout_change.notify = layout_change;
	wl_signal_add(&server->output_layout->events.change, &server->layout_change);
	server->new_output.notify = new_output;
	wl_signal_add(&server->backend->events.new_output, &server->new_output);
}
