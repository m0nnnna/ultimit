/*
 * ipc.c: a small control socket for scripts and tests ("ultimitctl").
 *
 * Socket: $XDG_RUNTIME_DIR/ultimit-$WAYLAND_DISPLAY.sock, one command per
 * line, one JSON reply per line:
 *   state                  outputs, windows (geometry, chrome, flags), layers
 *   focus ID | close ID    act on a window by id
 *   move ID X Y            place a window's content top-left
 *   resize ID W H          ask a window for a new content size
 *   maximize ID | fullscreen ID | minimize ID    toggle
 *
 * Only the user running the compositor can connect (0700 runtime dir).
 */

#define _GNU_SOURCE /* accept4 */
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include "server.h"
#include "theme.h"

struct ipc_client {
	struct ul_server *server;
	int fd;
	struct wl_event_source *source;
	char buf[512];
	size_t len;
};

/* ---- tiny JSON writer ---------------------------------------------------- */

struct out {
	char *data;
	size_t len, cap;
};

static void put(struct out *o, const char *fmt, ...) {
	va_list ap;
	for (;;) {
		va_start(ap, fmt);
		int n = vsnprintf(o->data + o->len, o->cap - o->len, fmt, ap);
		va_end(ap);
		if (n >= 0 && (size_t)n < o->cap - o->len) {
			o->len += n;
			return;
		}
		o->cap = o->cap ? o->cap * 2 : 4096;
		o->data = realloc(o->data, o->cap);
	}
}

static void put_str(struct out *o, const char *s) {
	put(o, "\"");
	for (; s && *s; s++) {
		unsigned char c = *s;
		if (c == '"' || c == '\\') put(o, "\\%c", c);
		else if (c < 0x20) put(o, "\\u%04x", c);
		else put(o, "%c", c);
	}
	put(o, "\"");
}

static void put_box(struct out *o, struct wlr_box b) {
	put(o, "{\"x\":%d,\"y\":%d,\"width\":%d,\"height\":%d}", b.x, b.y, b.width, b.height);
}

static void write_state(struct ul_server *server, struct out *o) {
	put(o, "{\"outputs\":[");
	struct ul_output *output;
	bool first = true;
	wl_list_for_each(output, &server->outputs, link) {
		put(o, "%s{\"name\":", first ? "" : ",");
		put_str(o, output->wlr_output->name);
		put(o, ",\"full\":");
		put_box(o, output->full_area);
		put(o, ",\"usable\":");
		put_box(o, output->usable_area);
		put(o, ",\"refresh_mhz\":%d,\"adaptive_sync\":%s}", output->wlr_output->refresh,
			output->wlr_output->adaptive_sync_status == WLR_OUTPUT_ADAPTIVE_SYNC_ENABLED ?
			"true" : "false");
		first = false;
	}

	put(o, "],\"windows\":[");
	first = true;
	struct ul_view *view;
	wl_list_for_each(view, &server->views, link) {
		int bar = view->ssd ? UL_TITLEBAR_H : 0;
		put(o, "%s{\"id\":%u,\"type\":\"%s\",\"app_id\":", first ? "" : ",", view->id,
			view->type == UL_VIEW_XDG ? "xdg" : "xwayland");
		put_str(o, view_app_id(view));
		put(o, ",\"title\":");
		put_str(o, view_title(view));
		put(o, ",\"content\":");
		put_box(o, (struct wlr_box){ view->x, view->y, view->width, view->height });
		put(o, ",\"frame\":");
		put_box(o, (struct wlr_box){ view->x - UL_BORDER, view->y - bar - UL_BORDER,
			view->width + 2 * UL_BORDER, view->height + bar + 2 * UL_BORDER });
		put(o, ",\"tree\":{\"x\":%d,\"y\":%d}", view->tree->node.x, view->tree->node.y);
		put(o, ",\"geometry_offset\":");
		put_box(o, view_geometry_offset(view));
		put(o, ",\"ssd\":%s,\"focused\":%s,\"mapped\":%s,\"minimized\":%s,"
			"\"maximized\":%s,\"fullscreen\":%s,\"animating\":%s}",
			view->ssd ? "true" : "false",
			server->focused_view == view ? "true" : "false",
			view->mapped ? "true" : "false",
			view->minimized ? "true" : "false",
			view->maximized ? "true" : "false",
			view->fullscreen ? "true" : "false",
			anim_running(view) ? "true" : "false");
		first = false;
	}

	put(o, "],\"layers\":[");
	first = true;
	wl_list_for_each(output, &server->outputs, link) {
		for (int i = 0; i < 4; i++) {
			struct ul_layer_surface *l;
			wl_list_for_each(l, &output->layer_surfaces[i], link) {
				struct wlr_layer_surface_v1 *ls = l->layer_surface;
				put(o, "%s{\"namespace\":", first ? "" : ",");
				put_str(o, ls->namespace);
				put(o, ",\"layer\":%d,\"output\":", i);
				put_str(o, output->wlr_output->name);
				put(o, ",\"box\":");
				put_box(o, (struct wlr_box){ l->scene->tree->node.x, l->scene->tree->node.y,
					ls->current.actual_width, ls->current.actual_height });
				put(o, ",\"exclusive_zone\":%d,\"mapped\":%s}", ls->current.exclusive_zone,
					l->mapped ? "true" : "false");
				first = false;
			}
		}
	}
	put(o, "],\"focused_layer\":%s}", server->focused_layer ? "true" : "false");
}

/* ---- commands ------------------------------------------------------------ */

static struct ul_view *find_view(struct ul_server *server, unsigned id) {
	struct ul_view *view;
	wl_list_for_each(view, &server->views, link) {
		if (view->id == id) return view;
	}
	return NULL;
}

static void run_command(struct ul_server *server, char *line, struct out *o) {
	char cmd[32] = {0};
	unsigned id = 0;
	int a = 0, b = 0;
	int n = sscanf(line, "%31s %u %d %d", cmd, &id, &a, &b);
	if (n < 1) {
		put(o, "{\"error\":\"empty command\"}");
		return;
	}
	if (strcmp(cmd, "state") == 0) {
		write_state(server, o);
		return;
	}
	struct ul_view *view = n >= 2 ? find_view(server, id) : NULL;
	if (!view) {
		put(o, "{\"error\":\"unknown command or window id\"}");
		return;
	}
	if (strcmp(cmd, "focus") == 0) {
		view_focus(view);
	} else if (strcmp(cmd, "close") == 0) {
		view_close(view);
	} else if (strcmp(cmd, "move") == 0 && n == 4) {
		view_set_position(view, a, b);
	} else if (strcmp(cmd, "resize") == 0 && n == 4) {
		view_request_size(view, a, b);
	} else if (strcmp(cmd, "maximize") == 0) {
		view_set_maximized(view, !view->maximized);
	} else if (strcmp(cmd, "fullscreen") == 0) {
		view_set_fullscreen(view, !view->fullscreen);
	} else if (strcmp(cmd, "minimize") == 0) {
		view_set_minimized(view, !view->minimized);
	} else {
		put(o, "{\"error\":\"unknown command\"}");
		return;
	}
	put(o, "{\"ok\":true}");
}

/* ---- socket plumbing ----------------------------------------------------- */

static void client_close(struct ipc_client *c) {
	wl_event_source_remove(c->source);
	close(c->fd);
	free(c);
}

static int client_readable(int fd, uint32_t mask, void *data) {
	struct ipc_client *c = data;
	if (mask & (WL_EVENT_HANGUP | WL_EVENT_ERROR)) {
		client_close(c);
		return 0;
	}
	ssize_t n = read(fd, c->buf + c->len, sizeof(c->buf) - 1 - c->len);
	if (n <= 0) {
		client_close(c);
		return 0;
	}
	c->len += n;
	c->buf[c->len] = '\0';
	char *nl;
	while ((nl = strchr(c->buf, '\n'))) {
		*nl = '\0';
		struct out o = {0};
		run_command(c->server, c->buf, &o);
		put(&o, "\n");
		/* Replies are small; a blocking write on a local socket is fine. */
		size_t off = 0;
		while (off < o.len) {
			ssize_t w = write(fd, o.data + off, o.len - off);
			if (w < 0 && errno != EINTR) break;
			if (w > 0) off += w;
		}
		free(o.data);
		size_t rest = c->len - (nl + 1 - c->buf);
		memmove(c->buf, nl + 1, rest + 1);
		c->len = rest;
	}
	if (c->len >= sizeof(c->buf) - 1) {
		client_close(c); /* line too long */
	}
	return 0;
}

static int server_acceptable(int fd, uint32_t mask, void *data) {
	struct ul_server *server = data;
	int cfd = accept4(fd, NULL, NULL, SOCK_CLOEXEC);
	if (cfd < 0) {
		return 0;
	}
	struct ipc_client *c = calloc(1, sizeof(*c));
	c->server = server;
	c->fd = cfd;
	c->source = wl_event_loop_add_fd(wl_display_get_event_loop(server->display), cfd,
		WL_EVENT_READABLE, client_readable, c);
	return 0;
}

void ipc_init(struct ul_server *server, const char *wayland_socket) {
	const char *dir = getenv("XDG_RUNTIME_DIR");
	if (!dir) {
		return;
	}
	struct sockaddr_un addr = { .sun_family = AF_UNIX };
	snprintf(addr.sun_path, sizeof(addr.sun_path), "%s/ultimit-%s.sock", dir, wayland_socket);
	int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0) {
		return;
	}
	unlink(addr.sun_path);
	if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 || listen(fd, 8) < 0) {
		wlr_log(WLR_ERROR, "ultimitctl socket %s: %s", addr.sun_path, strerror(errno));
		close(fd);
		return;
	}
	server->ipc_fd = fd;
	snprintf(server->ipc_path, sizeof(server->ipc_path), "%s", addr.sun_path);
	wl_event_loop_add_fd(wl_display_get_event_loop(server->display), fd,
		WL_EVENT_READABLE, server_acceptable, server);
	setenv("ULTIMIT_SOCK", addr.sun_path, true);
	wlr_log(WLR_INFO, "ultimitctl socket: %s", addr.sun_path);
}

void ipc_finish(struct ul_server *server) {
	if (server->ipc_fd > 0) {
		close(server->ipc_fd);
		unlink(server->ipc_path);
	}
}
