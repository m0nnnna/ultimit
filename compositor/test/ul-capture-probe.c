/*
 * ul-capture-probe: test client for window and output capture.
 *
 *   ul-capture-probe APP_ID [OUT.ppm]    capture the toplevel whose app_id
 *                                        contains APP_ID
 *   ul-capture-probe --output [OUT.ppm]  capture the first output
 *
 * Binds ext-foreign-toplevel-list and the image capture source managers,
 * makes a copy-capture session, captures one frame into a wl_shm buffer and
 * prints one line:  size WxH nonzero N alpha A
 * (N = pixels with any colour or alpha set, A = pixels with alpha != 0).
 * Exits non-zero if anything fails or nothing shows up within ten seconds.
 * With ULCP_STREAM_MS=N it keeps capturing on the same session for N ms and
 * prints a line per frame (a resized window shows up as a new size).
 */

#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include "ext-foreign-toplevel-list-v1-client-protocol.h"
#include "ext-image-capture-source-v1-client-protocol.h"
#include "ext-image-copy-capture-v1-client-protocol.h"

#define TIMEOUT_MS 10000

/* DRM fourcc codes (wl_shm uses the same values except ARGB/XRGB8888). */
#define FMT_ABGR8888 0x34324241
#define FMT_XBGR8888 0x34324258
#define FMT_RGB888 0x34324752
#define FMT_BGR888 0x34324742

static struct wl_shm *shm;
static struct wl_output *output;
static struct ext_foreign_toplevel_list_v1 *list;
static struct ext_foreign_toplevel_image_capture_source_manager_v1 *toplevel_mgr;
static struct ext_output_image_capture_source_manager_v1 *output_mgr;
static struct ext_image_copy_capture_manager_v1 *copy_mgr;

static const char *want_app;
static bool want_output;

struct toplevel {
	struct ext_foreign_toplevel_handle_v1 *handle;
	char *app_id;
	bool done;
};
static struct toplevel *picked;
static struct toplevel tops[64];
static int ntops;

static struct {
	uint32_t width, height;
	uint32_t shm_format;
	bool have_format, done, stopped;
} session;

static struct {
	bool ready, failed;
	uint32_t reason;
} frame_state;

static void die(const char *msg) {
	fprintf(stderr, "ul-capture-probe: %s\n", msg);
	exit(1);
}

/* ---- toplevel list --------------------------------------------------------- */

static void h_closed(void *d, struct ext_foreign_toplevel_handle_v1 *h) {}
static void h_done(void *d, struct ext_foreign_toplevel_handle_v1 *h) {
	struct toplevel *t = d;
	t->done = true;
	if (!picked && want_app && t->app_id && strstr(t->app_id, want_app)) {
		picked = t;
	}
}
static void h_title(void *d, struct ext_foreign_toplevel_handle_v1 *h, const char *s) {}
static void h_app_id(void *d, struct ext_foreign_toplevel_handle_v1 *h, const char *s) {
	struct toplevel *t = d;
	free(t->app_id);
	t->app_id = strdup(s);
}
static void h_identifier(void *d, struct ext_foreign_toplevel_handle_v1 *h, const char *s) {}

static const struct ext_foreign_toplevel_handle_v1_listener handle_listener = {
	.closed = h_closed, .done = h_done, .title = h_title,
	.app_id = h_app_id, .identifier = h_identifier,
};

static void l_toplevel(void *d, struct ext_foreign_toplevel_list_v1 *l,
		struct ext_foreign_toplevel_handle_v1 *h) {
	if (ntops >= 64) return;
	struct toplevel *t = &tops[ntops++];
	t->handle = h;
	ext_foreign_toplevel_handle_v1_add_listener(h, &handle_listener, t);
}
static void l_finished(void *d, struct ext_foreign_toplevel_list_v1 *l) {}
static const struct ext_foreign_toplevel_list_v1_listener list_listener = {
	.toplevel = l_toplevel, .finished = l_finished,
};

/* ---- session / frame --------------------------------------------------------- */

static void s_buffer_size(void *d, struct ext_image_copy_capture_session_v1 *s, uint32_t w, uint32_t h) {
	session.width = w;
	session.height = h;
}
static void s_shm_format(void *d, struct ext_image_copy_capture_session_v1 *s, uint32_t f) {
	if (!session.have_format) {
		session.shm_format = f;
		session.have_format = true;
	}
}
static void s_dmabuf_device(void *d, struct ext_image_copy_capture_session_v1 *s, struct wl_array *a) {}
static void s_dmabuf_format(void *d, struct ext_image_copy_capture_session_v1 *s, uint32_t f, struct wl_array *a) {}
static void s_done(void *d, struct ext_image_copy_capture_session_v1 *s) { session.done = true; }
static void s_stopped(void *d, struct ext_image_copy_capture_session_v1 *s) { session.stopped = true; }
static const struct ext_image_copy_capture_session_v1_listener session_listener = {
	.buffer_size = s_buffer_size, .shm_format = s_shm_format,
	.dmabuf_device = s_dmabuf_device, .dmabuf_format = s_dmabuf_format,
	.done = s_done, .stopped = s_stopped,
};

static void f_transform(void *d, struct ext_image_copy_capture_frame_v1 *f, uint32_t t) {}
static void f_damage(void *d, struct ext_image_copy_capture_frame_v1 *f, int32_t x, int32_t y, int32_t w, int32_t h) {}
static void f_time(void *d, struct ext_image_copy_capture_frame_v1 *f, uint32_t hi, uint32_t lo, uint32_t ns) {}
static void f_ready(void *d, struct ext_image_copy_capture_frame_v1 *f) { frame_state.ready = true; }
static void f_failed(void *d, struct ext_image_copy_capture_frame_v1 *f, uint32_t reason) {
	frame_state.failed = true;
	frame_state.reason = reason;
}
static const struct ext_image_copy_capture_frame_v1_listener frame_listener = {
	.transform = f_transform, .damage = f_damage, .presentation_time = f_time,
	.ready = f_ready, .failed = f_failed,
};

/* ---- registry ---------------------------------------------------------------- */

static void reg_global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t version) {
	if (!strcmp(iface, wl_shm_interface.name)) {
		shm = wl_registry_bind(r, name, &wl_shm_interface, 1);
	} else if (!strcmp(iface, wl_output_interface.name) && !output) {
		output = wl_registry_bind(r, name, &wl_output_interface, 1);
	} else if (!strcmp(iface, ext_foreign_toplevel_list_v1_interface.name)) {
		list = wl_registry_bind(r, name, &ext_foreign_toplevel_list_v1_interface, 1);
		ext_foreign_toplevel_list_v1_add_listener(list, &list_listener, NULL);
	} else if (!strcmp(iface, ext_foreign_toplevel_image_capture_source_manager_v1_interface.name)) {
		toplevel_mgr = wl_registry_bind(r, name,
			&ext_foreign_toplevel_image_capture_source_manager_v1_interface, 1);
	} else if (!strcmp(iface, ext_output_image_capture_source_manager_v1_interface.name)) {
		output_mgr = wl_registry_bind(r, name,
			&ext_output_image_capture_source_manager_v1_interface, 1);
	} else if (!strcmp(iface, ext_image_copy_capture_manager_v1_interface.name)) {
		copy_mgr = wl_registry_bind(r, name, &ext_image_copy_capture_manager_v1_interface, 1);
	}
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t name) {}
static const struct wl_registry_listener registry_listener = { reg_global, reg_remove };

/* ---- helpers ----------------------------------------------------------------- */

static int64_t now_ms(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* Dispatch events until *flag (or the optional second flag) is set. */
static bool wait_for(struct wl_display *display, const bool *flag, const bool *flag2,
		const char *what, int64_t timeout_ms, bool soft) {
	int64_t end = now_ms() + timeout_ms;
	while (!*flag && !(flag2 && *flag2)) {
		if (wl_display_dispatch_pending(display) < 0) die("display error");
		if (*flag || (flag2 && *flag2)) break;
		wl_display_flush(display);
		int64_t left = end - now_ms();
		if (left <= 0) {
			if (soft) return false;
			fprintf(stderr, "ul-capture-probe: timed out waiting for %s\n", what);
			exit(1);
		}
		struct pollfd pfd = { wl_display_get_fd(display), POLLIN, 0 };
		if (poll(&pfd, 1, (int)left) > 0 && wl_display_dispatch(display) < 0) die("display error");
	}
	return true;
}

static int shm_fd(size_t size) {
	int fd = memfd_create("ul-capture-probe", MFD_CLOEXEC);
	if (fd < 0 || ftruncate(fd, size) < 0) die("memfd");
	return fd;
}

int main(int argc, char **argv) {
	const char *out_path = NULL;
	if (argc >= 2 && !strcmp(argv[1], "--output")) {
		want_output = true;
		if (argc >= 3) out_path = argv[2];
	} else if (argc >= 2) {
		want_app = argv[1];
		if (argc >= 3) out_path = argv[2];
	} else {
		fprintf(stderr, "usage: %s APP_ID|--output [OUT.ppm]\n", argv[0]);
		return 2;
	}

	struct wl_display *display = wl_display_connect(NULL);
	if (!display) die("cannot connect to the compositor");
	struct wl_registry *registry = wl_display_get_registry(display);
	wl_registry_add_listener(registry, &registry_listener, NULL);
	wl_display_roundtrip(display);
	wl_display_roundtrip(display);
	if (!shm || !copy_mgr) die("compositor lacks wl_shm or ext_image_copy_capture_manager_v1");

	struct ext_image_capture_source_v1 *source;
	if (want_output) {
		if (!output_mgr || !output) die("no ext_output_image_capture_source_manager_v1 / wl_output");
		source = ext_output_image_capture_source_manager_v1_create_source(output_mgr, output);
	} else {
		if (!list || !toplevel_mgr) die("no ext_foreign_toplevel_list_v1 / toplevel capture source manager");
		int64_t end = now_ms() + TIMEOUT_MS;
		while (!picked && now_ms() < end) {
			wl_display_roundtrip(display);
			if (!picked) usleep(100000);
		}
		if (!picked) {
			fprintf(stderr, "ul-capture-probe: no toplevel with app_id matching '%s' (saw %d)\n",
				want_app, ntops);
			return 1;
		}
		source = ext_foreign_toplevel_image_capture_source_manager_v1_create_source(
			toplevel_mgr, picked->handle);
	}
	struct ext_image_copy_capture_session_v1 *sess =
		ext_image_copy_capture_manager_v1_create_session(copy_mgr, source, 0);
	ext_image_copy_capture_session_v1_add_listener(sess, &session_listener, NULL);

	/* A resize between constraints and capture fails the frame with
	 * buffer_constraints; start over with the new size a few times. */
	const char *stream = getenv("ULCP_STREAM_MS");
	int64_t stream_end = stream ? now_ms() + atoi(stream) : 0;
	bool need_constraints = true;
	for (int attempt = 0; attempt < 4;) {
		if (need_constraints) {
			wait_for(display, &session.done, &session.stopped, "session constraints", TIMEOUT_MS, false);
		}
		need_constraints = false;
		if (session.stopped) die("session stopped");
		if (!session.have_format || session.width == 0 || session.height == 0) die("no shm format / size");
		uint32_t fmt = session.shm_format;
		int bpp = fmt == FMT_BGR888 || fmt == FMT_RGB888 ? 3 : 4;
		if (bpp == 4 && fmt != WL_SHM_FORMAT_ARGB8888 && fmt != WL_SHM_FORMAT_XRGB8888 &&
				fmt != FMT_ABGR8888 && fmt != FMT_XBGR8888) {
			fprintf(stderr, "ul-capture-probe: unsupported shm format 0x%x\n", fmt);
			return 1;
		}
		uint32_t w = session.width, h = session.height, stride = w * bpp;
		size_t size = (size_t)stride * h;
		int fd = shm_fd(size);
		uint8_t *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
		if (data == MAP_FAILED) die("mmap");
		memset(data, 0, size);
		struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
		struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, w, h, stride, fmt);
		wl_shm_pool_destroy(pool);
		close(fd);

		memset(&frame_state, 0, sizeof(frame_state));
		struct ext_image_copy_capture_frame_v1 *frame = ext_image_copy_capture_session_v1_create_frame(sess);
		ext_image_copy_capture_frame_v1_add_listener(frame, &frame_listener, NULL);
		ext_image_copy_capture_frame_v1_attach_buffer(frame, buffer);
		ext_image_copy_capture_frame_v1_damage_buffer(frame, 0, 0, w, h);
		ext_image_copy_capture_frame_v1_capture(frame);
		session.done = false;
		int64_t limit = stream ? stream_end - now_ms() : TIMEOUT_MS;
		if (stream && limit < 1) limit = 1;
		if (!wait_for(display, &frame_state.ready, &frame_state.failed, "the captured frame", limit, stream != NULL)) {
			return 0; /* streaming: the window went quiet, that's fine */
		}
		if (frame_state.failed) {
			attempt++;
			need_constraints = true;
			ext_image_copy_capture_frame_v1_destroy(frame);
			wl_buffer_destroy(buffer);
			munmap(data, size);
			if (frame_state.reason == EXT_IMAGE_COPY_CAPTURE_FRAME_V1_FAILURE_REASON_BUFFER_CONSTRAINTS) continue;
			fprintf(stderr, "ul-capture-probe: frame failed (reason %u)\n", frame_state.reason);
			return 1;
		}

		/* In memory order: BGRA for ARGB8888/XRGB8888 (little endian), RGBA
		 * for ABGR8888/XBGR8888, RGB for BGR888 (DRM names are reversed). */
		bool bgr_order = fmt == WL_SHM_FORMAT_ARGB8888 || fmt == WL_SHM_FORMAT_XRGB8888 || fmt == FMT_RGB888;
		bool has_alpha = fmt == WL_SHM_FORMAT_ARGB8888 || fmt == FMT_ABGR8888;
		long nonzero = 0, alpha = 0;
		for (size_t i = 0; i < size; i += bpp) {
			bool any = false;
			for (int c = 0; c < bpp; c++) any |= data[i + c] != 0;
			if (any) nonzero++;
			if (!has_alpha || data[i + 3]) alpha++;
		}
		printf("size %ux%u nonzero %ld alpha %ld\n", w, h, nonzero, alpha);
		if (out_path) {
			FILE *f = fopen(out_path, "wb");
			if (!f) die("cannot write the output file");
			fprintf(f, "P6\n%u %u\n255\n", w, h);
			for (size_t i = 0; i < size; i += bpp) {
				uint8_t rgb[3];
				if (bgr_order) {
					rgb[0] = data[i + 2]; rgb[1] = data[i + 1]; rgb[2] = data[i];
				} else {
					rgb[0] = data[i]; rgb[1] = data[i + 1]; rgb[2] = data[i + 2];
				}
				fwrite(rgb, 1, 3, f);
			}
			fclose(f);
		}
		fflush(stdout);
		wl_buffer_destroy(buffer);
		munmap(data, size);
		if (stream && now_ms() < stream_end) continue;
		return 0;
	}
	die("window kept resizing; gave up");
	return 1;
}
