/*
 * ipc.c: a small control socket for scripts and tests ("ultimitctl").
 *
 * Socket: $XDG_RUNTIME_DIR/ultimit-$WAYLAND_DISPLAY.sock, one command per
 * line, one JSON reply per line:
 *   state                  outputs, windows (geometry, chrome, flags), layers, snap_widths
 *   focus ID | close ID    act on a window by id
 *   move ID X Y            place a window's content top-left
 *   resize ID W H          ask a window for a new content size
 *   maximize ID | fullscreen ID | minimize ID    toggle
 *   reload                 re-read ~/.config/ultimit/compositor.ini
 *   keys                   every keybinding (keys.c) as JSON, for cheat sheets
 *   snap ID left|right|restore|maximize   tile a window (view.c); repeating
 *                          left/right steps through the snap widths like Super+Left/Right
 *   subscribe              keep the connection open and receive events, one
 *                          JSON line each: {"event":"alttab","action":"show"|
 *                          "move"|"hide","index":N,"items":[...]} (alttab.c),
 *                          {"event":"dismiss","keep":NAME} (ipc_emit_dismiss)
 *   drag ID X Y            test hook: start a titlebar drag of window ID and move
 *                          the pointer to layout X,Y, as if the button were held;
 *                          "drag-release" drops it (the real snap code runs)
 *
 * Only the user running the compositor can connect (0700 runtime dir).
 */

#define _GNU_SOURCE /* accept4 */
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <wlr/backend/headless.h>
#include <wlr/backend/multi.h>
#include "server.h"
#include "json.h"
#include "theme.h"

struct ipc_client {
	struct wl_list link;
	bool subscribed;
	struct ul_server *server;
	int fd;
	struct wl_event_source *source;
	char buf[512];
	size_t len;
};

struct ipc_client;
static void client_close(struct ipc_client *c);
static struct wl_list clients = { &clients, &clients }; /* ipc_client.link */

static void write_state(struct ul_server *server, struct out *o) {
	put(o, "{\"outputs\":[");
	struct ul_output *output;
	bool first = true;
	wl_list_for_each(output, &server->outputs, link) {
		struct wlr_output *wo = output->wlr_output;
		char id[256];
		output_identity(wo, id, sizeof(id));
		put(o, "%s{\"name\":", first ? "" : ",");
		put_str(o, wo->name);
		put(o, ",\"id\":");
		put_str(o, id);
		put(o, ",\"description\":");
		put_str(o, wo->description ? wo->description : "");
		put(o, ",\"enabled\":%s,\"primary\":%s,\"scale\":%.3f,\"transform\":%d,\"mode\":{\"width\":%d,\"height\":%d}",
			wlr_output_layout_get(server->output_layout, wo) ? "true" : "false",
			output_primary(server) == output ? "true" : "false",
			wo->scale, wo->transform, wo->width, wo->height);
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
		/* Where the shell's rail shows this window (null until the shell said). */
		put(o, ",\"rail\":");
		if (view->has_rail_rect) {
			put_box(o, view->rail_rect);
		} else {
			put(o, "null");
		}
		/* Titlebar buttons (minimize, maximize, close) as layout boxes. */
		put(o, ",\"buttons\":[");
		for (int i = 0; view->ssd && i < 3; i++) {
			put(o, "%s", i ? "," : "");
			put_box(o, (struct wlr_box){ view->x - UL_BORDER + view->deco.button_x[i],
				view->y - bar - UL_BORDER, view->deco.button_w[i], UL_TITLEBAR_H });
		}
		put(o, "]");
		put(o, ",\"geometry_offset\":");
		put_box(o, view_geometry_offset(view));
		put(o, ",\"ssd\":%s,\"focused\":%s,\"mapped\":%s,\"minimized\":%s,"
			"\"maximized\":%s,\"fullscreen\":%s,\"above\":%s,\"animating\":%s,\"snapped\":%s,\"snap_step\":%d,\"tiled\":%u}",
			view->ssd ? "true" : "false",
			server->focused_view == view ? "true" : "false",
			view->mapped ? "true" : "false",
			view->minimized ? "true" : "false",
			view->maximized ? "true" : "false",
			view->fullscreen ? "true" : "false",
			view->above ? "true" : "false",
			anim_running(view) ? "true" : "false",
			view->snapped == UL_SNAP_LEFT ? "\"left\"" :
			view->snapped == UL_SNAP_RIGHT ? "\"right\"" : "null",
			view->snapped ? view->snap_step : 0,
			view->type == UL_VIEW_XDG ? view->xdg_toplevel->current.tiled : 0);
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
	put(o, "],\"focused_layer\":%s,\"locked\":%s,\"idle_inhibitors\":%d,\"motion\":%s,\"snap_widths\":[",
		server->focused_layer ? "true" : "false", server->locked ? "true" : "false",
		server->idle_inhibitors, anim_motion() ? "true" : "false");
	for (int i = 0; i < server->config.snap_count; i++) {
		put(o, "%s%.4f", i ? "," : "", server->config.snap_widths[i]);
	}
	put(o, "]}");
}

/* ---- commands ------------------------------------------------------------ */

static void find_headless(struct wlr_backend *backend, void *data) {
	if (wlr_backend_is_headless(backend)) {
		*(struct wlr_backend **)data = backend;
	}
}

#define find_view view_by_id

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
	if (strcmp(cmd, "cursor-theme") == 0) {
		/* cursor-theme NAME [SIZE]: the shell sends this on a skin change. */
		char name[128] = {0};
		int size = 0;
		if (sscanf(line, "%*s %127s %d", name, &size) < 1) {
			put(o, "{\"error\":\"usage: cursor-theme NAME [SIZE]\"}");
			return;
		}
		put(o, input_set_cursor_theme(server, name, size) ?
			"{\"ok\":true}" : "{\"error\":\"cannot load cursor theme\"}");
		return;
	}
	if (strcmp(cmd, "primary") == 0) {
		/* primary NAME: make that output the main display (Settings > Display saves it too). */
		char name[64] = {0};
		struct ul_output *out, *hit = NULL;
		if (sscanf(line, "%*s %63s", name) == 1) {
			wl_list_for_each(out, &server->outputs, link) {
				if (strcmp(out->wlr_output->name, name) == 0) hit = out;
			}
		}
		if (!hit) {
			put(o, "{\"error\":\"usage: primary OUTPUT\"}");
			return;
		}
		wl_list_for_each(out, &server->outputs, link) {
			out->primary = out == hit;
		}
		xwayland_sync_primary(server);
		put(o, "{\"ok\":true}");
		return;
	}
	if (strcmp(cmd, "test-output") == 0) {
		/* test-output add W H | remove NAME: plug / unplug a virtual monitor (headless only). */
		char what[16] = {0}, arg[64] = {0};
		int w = 0, h = 0;
		sscanf(line, "%*s %15s %63s %d", what, arg, &h);
		if (strcmp(what, "add") == 0 && (w = atoi(arg)) > 0 && h > 0) {
			struct wlr_backend *hb = wlr_backend_is_headless(server->backend) ? server->backend : NULL;
			if (!hb && wlr_backend_is_multi(server->backend)) {
				wlr_multi_for_each_backend(server->backend, find_headless, &hb);
			}
			struct wlr_output *wo = hb ? wlr_headless_add_output(hb, w, h) : NULL;
			if (!wo) {
				put(o, "{\"error\":\"no headless backend\"}");
				return;
			}
			put(o, "{\"ok\":true,\"name\":");
			put_str(o, wo->name);
			put(o, "}");
			return;
		}
		if (strcmp(what, "remove") == 0) {
			struct ul_output *out;
			wl_list_for_each(out, &server->outputs, link) {
				if (strcmp(out->wlr_output->name, arg) == 0) {
					wlr_output_destroy(out->wlr_output);
					put(o, "{\"ok\":true}");
					return;
				}
			}
			put(o, "{\"error\":\"no such output\"}");
			return;
		}
		put(o, "{\"error\":\"usage: test-output add W H | remove NAME\"}");
		return;
	}
	if (strcmp(cmd, "motion") == 0) {
		/* motion on|off: window animations follow the shell's motion setting. */
		char what[8] = {0};
		if (sscanf(line, "%*s %7s", what) != 1 || (strcmp(what, "on") && strcmp(what, "off"))) {
			put(o, "{\"error\":\"usage: motion on|off\"}");
			return;
		}
		anim_set_motion(strcmp(what, "on") == 0);
		put(o, "{\"ok\":true}");
		return;
	}
	if (strcmp(cmd, "skin") == 0) {
		/* skin PANEL FG DIM LINE LINE_STRONG ACCENT BAD [HL] [FAMILY]: window chrome colors + title font,
		 * sent by the shell at startup and on a skin change. */
		if (!skin_parse(&server->skin, line + strlen("skin"))) {
			put(o, "{\"error\":\"usage: skin PANEL FG DIM LINE LINE_STRONG ACCENT BAD (#rrggbb[aa])\"}");
			return;
		}
		decoration_restyle_all(server);
		put(o, "{\"ok\":true}");
		return;
	}
	if (strcmp(cmd, "release-keys") == 0) {
		/* the shell sends this after a resume: drop keys whose release got lost */
		input_release_keys(server);
		put(o, "{\"ok\":true}");
		return;
	}
	if (strcmp(cmd, "keys") == 0) {
		keys_write_json(o);
		return;
	}
	if (strcmp(cmd, "drag-release") == 0) {
		input_test_drag(server, NULL, 0, 0, true);
		put(o, "{\"ok\":true}");
		return;
	}
	if (strcmp(cmd, "snap") == 0) {
		char what[16] = {0};
		struct ul_view *v = sscanf(line, "%*s %u %15s", &id, what) == 2 ? find_view(server, id) : NULL;
		if (!v) {
			put(o, "{\"error\":\"usage: snap ID left|right|restore|maximize\"}");
			return;
		}
		if (!strcmp(what, "left") || !strcmp(what, "right")) {
			enum ul_snap side = !strcmp(what, "left") ? UL_SNAP_LEFT : UL_SNAP_RIGHT;
			view_snap(v, side, v->snapped == side ? v->snap_step + 1 : 0);
		} else if (!strcmp(what, "restore")) {
			view_restore(v);
		} else if (!strcmp(what, "maximize")) {
			view_set_maximized(v, true);
		} else {
			put(o, "{\"error\":\"unknown snap target\"}");
			return;
		}
		put(o, "{\"ok\":true}");
		return;
	}
	if (strcmp(cmd, "drag") == 0) {
		int x, y;
		struct ul_view *v = sscanf(line, "%*s %u %d %d", &id, &x, &y) == 3 ? find_view(server, id) : NULL;
		if (!v) {
			put(o, "{\"error\":\"usage: drag ID X Y\"}");
			return;
		}
		input_test_drag(server, v, x, y, false);
		put(o, "{\"ok\":true}");
		return;
	}
	if (strcmp(cmd, "reload") == 0) {
		config_reload(server);
		put(o, "{\"ok\":true}");
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
		view_clear_snap(view);
		view_set_position(view, a, b);
	} else if (strcmp(cmd, "resize") == 0 && n == 4) {
		view_clear_snap(view);
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

/* ---- events ---------------------------------------------------------------- */

/* Send one JSON line to every subscriber. A subscriber that stops reading
 * (full socket buffer) is dropped rather than waited for. */
void ipc_broadcast(const char *line) {
	size_t len = strlen(line);
	struct ipc_client *c, *tmp;
	wl_list_for_each_safe(c, tmp, &clients, link) {
		if (!c->subscribed) continue;
		ssize_t w = write(c->fd, line, len);
		if (w != (ssize_t)len) {
			client_close(c);
		}
	}
}

/* alttab.c: the switcher opened ("show", with the window list), moved or closed. */
void ipc_emit_alttab(struct ul_server *server, const char *action) {
	struct out o = {0};
	put(&o, "{\"event\":\"alttab\",\"action\":\"%s\",\"index\":%d", action, server->alttab.index);
	if (strcmp(action, "hide") != 0) {
		put(&o, ",\"items\":[");
		for (int i = 0; i < server->alttab.count; i++) {
			struct ul_view *v = view_by_id(server, server->alttab.ids[i]);
			if (!v) continue;
			put(&o, "%s{\"id\":%u,\"app_id\":", i ? "," : "", v->id);
			put_str(&o, view_app_id(v));
			put(&o, ",\"title\":");
			put_str(&o, view_title(v));
			put(&o, ",\"minimized\":%s}", v->minimized ? "true" : "false");
		}
		put(&o, "]");
	}
	put(&o, "}\n");
	ipc_broadcast(o.data);
	free(o.data);
}

/* Tells the shell to close its menus and flyouts: a shortcut ran or a click
 * landed on another screen while one held the keyboard (keys.c, input.c).
 * "keep" names the panel that shortcut toggles itself ("launcher",
 * "clipboard", "shortcuts"), so closing it first doesn't undo the toggle. */
void ipc_emit_dismiss(const char *keep) {
	struct out o = {0};
	put(&o, "{\"event\":\"dismiss\",\"keep\":");
	put_str(&o, keep ? keep : "");
	put(&o, "}\n");
	ipc_broadcast(o.data);
	free(o.data);
}

/* ---- socket plumbing ----------------------------------------------------- */

static void client_close(struct ipc_client *c) {
	wl_list_remove(&c->link);
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
	if (n < 0 && (errno == EAGAIN || errno == EINTR)) {
		return 0;
	}
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
		bool subscribe = strcmp(c->buf, "subscribe") == 0;
		if (subscribe) {
			put(&o, "{\"ok\":true,\"subscribed\":true}");
		} else {
			run_command(c->server, c->buf, &o);
		}
		put(&o, "\n");
		/* The socket is non-blocking: a client that doesn't read its replies
		 * (socket buffer full) is dropped instead of stalling the compositor. */
		size_t off = 0;
		bool stuck = false;
		while (off < o.len) {
			ssize_t w = write(fd, o.data + off, o.len - off);
			if (w < 0 && errno != EINTR) {
				stuck = true;
				break;
			}
			if (w > 0) off += w;
		}
		free(o.data);
		if (stuck) {
			client_close(c);
			return 0;
		}
		if (subscribe) {
			c->subscribed = true;
		}
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
	int cfd = accept4(fd, NULL, NULL, SOCK_CLOEXEC | SOCK_NONBLOCK);
	if (cfd < 0) {
		return 0;
	}
	struct ipc_client *c = calloc(1, sizeof(*c));
	c->server = server;
	c->fd = cfd;
	wl_list_insert(&clients, &c->link);
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
