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

void server_update_backdrop(struct ul_server *server) {
	struct wlr_box box;
	wlr_output_layout_get_box(server->output_layout, NULL, &box);
	wlr_scene_node_set_position(&server->backdrop->node, box.x, box.y);
	wlr_scene_rect_set_size(server->backdrop, box.width, box.height);
	wlr_scene_optimized_blur_set_size(server->blur, box.width, box.height);
	lock_arrange(server);
}

void output_arrange(struct ul_output *output) {
	wlr_output_layout_get_box(output->server->output_layout, output->wlr_output,
		&output->full_area);
	layer_arrange(output);

	struct ul_view *view;
	wl_list_for_each(view, &output->server->views, link) {
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

	if (wlr_scene_output_needs_frame(scene_output)) {
		struct wlr_output_state state;
		wlr_output_state_init(&state);

		struct ul_view *game = fullscreen_view_on(output);
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
	output->wlr_output->data = NULL;
	struct ul_server *server = output->server;
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
	bool have_conf = config_output_lookup(wlr_output->name, &conf);
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
	struct wlr_output_mode *mode = wlr_output_preferred_mode(wlr_output);
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
	output->scene_output = wlr_scene_output_create(server->scene, wlr_output);
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
