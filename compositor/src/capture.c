/*
 * capture.c: screen capture for screen recorders, browsers and chat apps.
 *
 * Outputs use wlroots' ext-image-copy-capture source. Single windows need
 * ext_foreign_toplevel_image_capture_source_manager_v1, which wlroots 0.19
 * doesn't have (0.20 does), so it is implemented here: one capture source
 * per view that renders the window's surface tree (main surface, subsurfaces
 * and xdg popups, alpha kept, no Ultimit chrome) into a swapchain buffer and
 * copies it into whatever buffer the client attached. xdg-desktop-portal-wlr
 * uses this for "share a window" in OBS, Discord and browsers.
 *
 * The content is drawn straight from the surfaces' textures, not from the
 * scene graph, so a minimized or covered window can still be captured.
 */

#include <drm_fourcc.h>
#include <math.h>
#include <stdlib.h>
#include <time.h>
#include <wlr/interfaces/wlr_ext_image_capture_source_v1.h>
#include <wlr/render/pass.h>
#include <wlr/render/swapchain.h>
#include <wlr/types/wlr_buffer.h>
#include <wlr/types/wlr_ext_foreign_toplevel_list_v1.h>
#include <wlr/types/wlr_ext_image_capture_source_v1.h>
#include <wlr/types/wlr_ext_image_copy_capture_v1.h>
#include "ext-image-capture-source-v1-protocol.h"
#include "server.h"

struct ul_capture_source {
	struct wlr_ext_image_capture_source_v1 base;
	struct ul_view *view;
	struct wlr_swapchain *swapchain;
	size_t num_started;
	uint32_t signature;  /* hash of what was last announced as a frame */
	bool has_signature;
	struct wl_event_source *idle; /* a client asked for a frame; deliver it */
};

struct ul_capture_manager {
	struct wl_global *global;
	struct wl_listener display_destroy;
};

/* Scale to render at: the view's output scale for native Wayland clients
 * (so a HiDPI window isn't captured at half its pixels); X11 windows are
 * unscaled. */
static int capture_scale(struct ul_view *view) {
	if (view->type != UL_VIEW_XDG) {
		return 1;
	}
	struct ul_output *output = output_for_view(view);
	if (!output || output->wlr_output->scale < 1.0f) {
		return 1;
	}
	return (int)ceilf(output->wlr_output->scale);
}

/* ---- walking the surface tree -------------------------------------------- */

typedef void (*surface_cb)(struct wlr_surface *surface, int sx, int sy, void *data);

struct walk {
	surface_cb cb;
	void *data;
};

static void walk_iter(struct wlr_surface *surface, int sx, int sy, void *data) {
	struct walk *w = data;
	w->cb(surface, sx, sy, w->data);
}

/* Visit every mapped surface of the view in painting order, with positions
 * relative to the view's content origin (its xdg geometry's top-left). */
static void view_walk_surfaces(struct ul_view *view, surface_cb cb, void *data) {
	struct wlr_surface *root = view_surface(view);
	if (!root) {
		return;
	}
	struct walk w = { cb, data };
	wlr_surface_for_each_surface(root, walk_iter, &w);
	if (view->type == UL_VIEW_XDG) {
		wlr_xdg_surface_for_each_popup_surface(view->xdg_toplevel->base, walk_iter, &w);
	}
}

static void signature_cb(struct wlr_surface *surface, int sx, int sy, void *data) {
	uint32_t *sig = data;
	*sig = *sig * 31 + surface->current.seq;
	*sig = *sig * 31 + (uint32_t)(uintptr_t)surface;
	*sig = *sig * 31 + (uint32_t)sx * 7 + (uint32_t)sy;
}

struct draw {
	struct wlr_render_pass *pass;
	struct wlr_box origin; /* geometry offset to subtract */
	int scale;
};

static void draw_cb(struct wlr_surface *surface, int sx, int sy, void *data) {
	struct draw *d = data;
	struct wlr_texture *texture = wlr_surface_get_texture(surface);
	if (!texture) {
		return;
	}
	struct wlr_fbox src;
	wlr_surface_get_buffer_source_box(surface, &src);
	wlr_render_pass_add_texture(d->pass, &(struct wlr_render_texture_options){
		.texture = texture,
		.src_box = src,
		.dst_box = {
			.x = (sx - d->origin.x) * d->scale,
			.y = (sy - d->origin.y) * d->scale,
			.width = surface->current.width * d->scale,
			.height = surface->current.height * d->scale,
		},
		.transform = surface->current.transform,
		.blend_mode = WLR_RENDER_BLEND_MODE_PREMULTIPLIED,
	});
}

/* ---- swapchain ------------------------------------------------------------ */

static void capture_size(struct ul_view *view, int *w, int *h) {
	int scale = capture_scale(view);
	*w = view->width > 0 ? view->width * scale : 1;
	*h = view->height > 0 ? view->height * scale : 1;
}

/* (Re)create the swapchain for the view's current size and tell the
 * sessions about the new buffer constraints. */
static bool capture_update_constraints(struct ul_capture_source *source) {
	struct ul_server *server = source->view->server;
	int w, h;
	capture_size(source->view, &w, &h);
	if (source->swapchain && source->swapchain->width == w && source->swapchain->height == h) {
		return true;
	}
	/* The renderer's texture formats for the buffer type the allocator
	 * makes (wlroots keeps the render format list private). */
	uint32_t cap = server->allocator->buffer_caps & WLR_BUFFER_CAP_DMABUF ?
		WLR_BUFFER_CAP_DMABUF : WLR_BUFFER_CAP_SHM;
	const struct wlr_drm_format_set *formats =
		wlr_renderer_get_texture_formats(server->renderer, cap);
	if (!formats) {
		wlr_log(WLR_ERROR, "capture: renderer has no buffer formats");
		return false;
	}
	/* Alpha first so translucent windows keep their transparency. */
	const struct wlr_drm_format *format = wlr_drm_format_set_get(formats, DRM_FORMAT_ARGB8888);
	if (!format) {
		format = wlr_drm_format_set_get(formats, DRM_FORMAT_XRGB8888);
	}
	if (!format) {
		wlr_log(WLR_ERROR, "capture: no ARGB8888/XRGB8888 render format");
		return false;
	}
	struct wlr_swapchain *swapchain =
		wlr_swapchain_create(server->allocator, w, h, format);
	if (!swapchain) {
		wlr_log(WLR_ERROR, "capture: failed to create a %dx%d swapchain", w, h);
		return false;
	}
	wlr_swapchain_destroy(source->swapchain);
	source->swapchain = swapchain;
	return wlr_ext_image_capture_source_v1_set_constraints_from_swapchain(
		&source->base, swapchain, server->renderer);
}

/* ---- source interface ------------------------------------------------------ */

static void source_start(struct wlr_ext_image_capture_source_v1 *base, bool with_cursors) {
	struct ul_capture_source *source = wl_container_of(base, source, base);
	source->num_started++;
}

static void source_stop(struct wlr_ext_image_capture_source_v1 *base) {
	struct ul_capture_source *source = wl_container_of(base, source, base);
	if (source->num_started > 0) {
		source->num_started--;
	}
}

static void emit_frame(struct ul_capture_source *source) {
	pixman_region32_t damage;
	pixman_region32_init_rect(&damage, 0, 0, source->base.width, source->base.height);
	struct wlr_ext_image_capture_source_v1_frame_event event = { .damage = &damage };
	wl_signal_emit_mutable(&source->base.events.frame, &event);
	pixman_region32_fini(&damage);
}

static void idle_frame(void *data) {
	struct ul_capture_source *source = data;
	source->idle = NULL;
	emit_frame(source);
}

/* A client attached a buffer and wants the next frame; the session only asks
 * when it has unseen damage (always, for its first frame). */
static void source_schedule_frame(struct wlr_ext_image_capture_source_v1 *base) {
	struct ul_capture_source *source = wl_container_of(base, source, base);
	if (source->idle) {
		return;
	}
	struct wl_event_loop *loop = wl_display_get_event_loop(source->view->server->display);
	source->idle = wl_event_loop_add_idle(loop, idle_frame, source);
}

static void source_copy_frame(struct wlr_ext_image_capture_source_v1 *base,
		struct wlr_ext_image_copy_capture_frame_v1 *frame,
		struct wlr_ext_image_capture_source_v1_frame_event *event) {
	struct ul_capture_source *source = wl_container_of(base, source, base);
	struct ul_view *view = source->view;
	struct ul_server *server = view->server;

	/* The window may have resized since the client allocated its buffer:
	 * announce the new size (the copy below then fails with
	 * buffer_constraints and the client retries with a fitting buffer). */
	if (!capture_update_constraints(source) || !source->swapchain) {
		wlr_ext_image_copy_capture_frame_v1_fail(frame,
			EXT_IMAGE_COPY_CAPTURE_FRAME_V1_FAILURE_REASON_UNKNOWN);
		return;
	}
	struct wlr_buffer *buffer = wlr_swapchain_acquire(source->swapchain);
	if (!buffer) {
		wlr_ext_image_copy_capture_frame_v1_fail(frame,
			EXT_IMAGE_COPY_CAPTURE_FRAME_V1_FAILURE_REASON_UNKNOWN);
		return;
	}
	struct wlr_render_pass *pass = wlr_renderer_begin_buffer_pass(server->renderer, buffer, NULL);
	if (!pass) {
		wlr_buffer_unlock(buffer);
		wlr_ext_image_copy_capture_frame_v1_fail(frame,
			EXT_IMAGE_COPY_CAPTURE_FRAME_V1_FAILURE_REASON_UNKNOWN);
		return;
	}
	/* Start transparent so windows with alpha stay see-through. */
	wlr_render_pass_add_rect(pass, &(struct wlr_render_rect_options){
		.box = { 0, 0, buffer->width, buffer->height },
		.color = { 0, 0, 0, 0 },
		.blend_mode = WLR_RENDER_BLEND_MODE_NONE,
	});
	struct draw d = {
		.pass = pass,
		.origin = view->type == UL_VIEW_XDG ? view_geometry_offset(view) : (struct wlr_box){0},
		.scale = capture_scale(view),
	};
	view_walk_surfaces(view, draw_cb, &d);
	bool ok = wlr_render_pass_submit(pass);

	if (ok && wlr_ext_image_copy_capture_frame_v1_copy_buffer(frame, buffer, server->renderer)) {
		struct timespec now;
		clock_gettime(CLOCK_MONOTONIC, &now);
		wlr_ext_image_copy_capture_frame_v1_ready(frame, WL_OUTPUT_TRANSFORM_NORMAL, &now);
	} else if (!ok) {
		wlr_ext_image_copy_capture_frame_v1_fail(frame,
			EXT_IMAGE_COPY_CAPTURE_FRAME_V1_FAILURE_REASON_UNKNOWN);
	}
	/* (copy_buffer already failed the frame itself when it returned false.) */
	wlr_buffer_unlock(buffer);
}

static const struct wlr_ext_image_capture_source_v1_interface source_impl = {
	.start = source_start,
	.stop = source_stop,
	.schedule_frame = source_schedule_frame,
	.copy_frame = source_copy_frame,
	/* No cursor source: the pointer isn't part of a window's contents. */
};

static struct ul_capture_source *capture_source_create(struct ul_view *view) {
	struct ul_capture_source *source = calloc(1, sizeof(*source));
	if (!source) {
		return NULL;
	}
	wlr_ext_image_capture_source_v1_init(&source->base, &source_impl);
	source->view = view;
	if (!capture_update_constraints(source)) {
		wlr_ext_image_capture_source_v1_finish(&source->base);
		free(source);
		return NULL;
	}
	return source;
}

/* Stops every session capturing this view (the clients get `stopped`). */
void capture_view_destroy(struct ul_view *view) {
	struct ul_capture_source *source = view->capture;
	if (!source) {
		return;
	}
	view->capture = NULL;
	if (source->idle) {
		wl_event_source_remove(source->idle);
	}
	wlr_ext_image_capture_source_v1_finish(&source->base);
	wlr_swapchain_destroy(source->swapchain);
	free(source);
}

/* Tell started sessions when the view's picture changed: a size change
 * re-announces the constraints, a commit anywhere in the surface tree
 * (including subsurfaces and popups) emits a frame. Cheap enough to call on
 * every commit and every output frame. */
void capture_view_commit(struct ul_view *view) {
	struct ul_capture_source *source = view->capture;
	if (!source || source->num_started == 0) {
		return;
	}
	uint32_t sig = 17;
	view_walk_surfaces(view, signature_cb, &sig);
	sig = sig * 31 + (uint32_t)view->width * 13 + (uint32_t)view->height;
	if (source->has_signature && sig == source->signature) {
		return;
	}
	source->signature = sig;
	source->has_signature = true;
	if (!capture_update_constraints(source)) {
		return;
	}
	emit_frame(source);
}

void capture_output_frame(struct ul_server *server) {
	struct ul_view *view;
	wl_list_for_each(view, &server->views, link) {
		if (view->capture && view->mapped) {
			capture_view_commit(view);
		}
	}
}

/* ---- ext_foreign_toplevel_image_capture_source_manager_v1 ------------------- */

static void manager_create_source(struct wl_client *client,
		struct wl_resource *manager_resource, uint32_t new_id,
		struct wl_resource *handle_resource) {
	struct wlr_ext_foreign_toplevel_handle_v1 *handle =
		wlr_ext_foreign_toplevel_handle_v1_from_resource(handle_resource);
	struct ul_view *view = handle ? handle->data : NULL;
	if (!view) {
		/* The toplevel is already gone: an inert source, whose sessions
		 * report `stopped` right away. */
		wlr_ext_image_capture_source_v1_create_resource(NULL, client, new_id);
		return;
	}
	if (!view->capture) {
		view->capture = capture_source_create(view);
		if (!view->capture) {
			wl_resource_post_no_memory(manager_resource);
			return;
		}
	}
	wlr_ext_image_capture_source_v1_create_resource(&view->capture->base, client, new_id);
}

static void manager_destroy(struct wl_client *client, struct wl_resource *resource) {
	wl_resource_destroy(resource);
}

static const struct ext_foreign_toplevel_image_capture_source_manager_v1_interface manager_impl = {
	.create_source = manager_create_source,
	.destroy = manager_destroy,
};

static void manager_bind(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
	struct wl_resource *resource = wl_resource_create(client,
		&ext_foreign_toplevel_image_capture_source_manager_v1_interface, version, id);
	if (!resource) {
		wl_client_post_no_memory(client);
		return;
	}
	wl_resource_set_implementation(resource, &manager_impl, data, NULL);
}

static void manager_display_destroy(struct wl_listener *listener, void *data) {
	struct ul_capture_manager *manager = wl_container_of(listener, manager, display_destroy);
	wl_list_remove(&manager->display_destroy.link);
	wl_global_destroy(manager->global);
	free(manager);
}

void capture_init(struct ul_server *server) {
	/* Window list (the handles a capture source is created from) and the
	 * copy protocol, plus wlroots' own per-output source. */
	server->ext_toplevel_list = wlr_ext_foreign_toplevel_list_v1_create(server->display, 1);
	wlr_ext_image_copy_capture_manager_v1_create(server->display, 1);
	wlr_ext_output_image_capture_source_manager_v1_create(server->display, 1);

	struct ul_capture_manager *manager = calloc(1, sizeof(*manager));
	if (!manager) {
		return;
	}
	manager->global = wl_global_create(server->display,
		&ext_foreign_toplevel_image_capture_source_manager_v1_interface, 1, manager, manager_bind);
	manager->display_destroy.notify = manager_display_destroy;
	wl_display_add_destroy_listener(server->display, &manager->display_destroy);
}
