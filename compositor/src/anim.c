/*
 * anim.c: the window open animation from the mockup. An accent line draws
 * outward from the center of the frame's top edge, then the frame appears
 * and the content wipes down from the top. Skipped for windows that map
 * fullscreen (games) and when ULTIMIT_ANIMATIONS=0.
 */

#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <scenefx/types/fx/clipped_region.h>
#include "server.h"
#include "theme.h"

#define LINE_MS 140
#define WIPE_MS 240
#define TICK_MS 8

static uint32_t now_ms(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* Ease-out cubic, close to the mockup's cubic-bezier(.2,.8,.2,1). */
static double ease(double t) {
	if (t < 0) t = 0;
	if (t > 1) t = 1;
	double u = 1 - t;
	return 1 - u * u * u;
}

static void set_chrome_enabled(struct ul_view *view, bool enabled) {
	struct ul_decoration *deco = &view->deco;
	wlr_scene_node_set_enabled(&deco->border->node, enabled);
	wlr_scene_node_set_enabled(&deco->titlebar->node, enabled && view->ssd);
	for (int i = 0; i < 4; i++) {
		wlr_scene_node_set_enabled(&deco->brackets[i]->node, enabled);
	}
}

static void finish(struct ul_view *view) {
	if (view->anim_timer) {
		wl_event_source_remove(view->anim_timer);
		view->anim_timer = NULL;
	}
	if (view->content) {
		wlr_scene_node_set_enabled(&view->content->node, true);
		wlr_scene_subsurface_tree_set_clip(&view->content->node, NULL);
	}
	wlr_scene_node_set_enabled(&view->deco.line->node, false);
	wlr_scene_node_set_enabled(&view->deco.shadow->node, true);
	set_chrome_enabled(view, true);
	decoration_update(view);
}

static int tick(void *data) {
	struct ul_view *view = data;
	struct ul_decoration *deco = &view->deco;
	uint32_t elapsed = now_ms() - view->anim_start;

	struct wlr_box geo = view_geometry_offset(view);
	int bar = view->ssd ? UL_TITLEBAR_H : 0;
	int fx = -UL_BORDER;
	int fy = -bar - UL_BORDER;
	int fw = view->width + 2 * UL_BORDER;

	if (elapsed < LINE_MS) {
		int w = fw * ease(elapsed / (double)LINE_MS);
		if (w < 2) w = 2;
		wlr_scene_rect_set_size(deco->line, w, UL_BRACKET_W);
		wlr_scene_node_set_position(&deco->line->node, fx + (fw - w) / 2, fy);
		wlr_scene_node_set_enabled(&deco->line->node, true);
		wlr_scene_node_set_enabled(&deco->shadow->node, false);
		set_chrome_enabled(view, false);
		wlr_scene_node_set_enabled(&view->content->node, false);
	} else if (elapsed < LINE_MS + WIPE_MS) {
		double p = ease((elapsed - LINE_MS) / (double)WIPE_MS);
		wlr_scene_rect_set_size(deco->line, fw, UL_BRACKET_W);
		wlr_scene_node_set_position(&deco->line->node, fx, fy);
		set_chrome_enabled(view, true);
		wlr_scene_node_set_enabled(&view->content->node, true);
		struct wlr_box clip = { geo.x, geo.y, view->width, (int)(view->height * p) };
		if (clip.height < 1) clip.height = 1;
		wlr_scene_subsurface_tree_set_clip(&view->content->node, &clip);
		/* The frame grows down with the content instead of appearing whole:
		 * shorten the border and lift the bottom brackets by what's still
		 * hidden (decoration_update puts everything back when done). */
		int hidden = view->height - clip.height;
		int fh = view->height + bar + 2 * UL_BORDER - hidden;
		wlr_scene_rect_set_size(deco->border, fw, fh);
		wlr_scene_rect_set_clipped_region(deco->border, (struct clipped_region){
			.corner_radius = 0,
			.corners = CORNER_LOCATION_NONE,
			.area = { UL_BORDER, UL_BORDER, fw - 2 * UL_BORDER, fh - 2 * UL_BORDER },
		});
		/* Bottom-right brackets (horizontal, vertical) sit on the current bottom. */
		wlr_scene_node_set_position(&deco->brackets[2]->node,
			fx + fw - UL_BRACKET_LEN, fy + fh - UL_BRACKET_W);
		wlr_scene_node_set_position(&deco->brackets[3]->node,
			fx + fw - UL_BRACKET_W, fy + fh - UL_BRACKET_LEN);
	} else {
		finish(view);
		return 0;
	}
	wl_event_source_timer_update(view->anim_timer, TICK_MS);
	return 0;
}

void anim_open(struct ul_view *view) {
	if (!anim_motion() || view->fullscreen || !view->content) {
		return;
	}
	anim_cancel(view);
	view->anim_start = now_ms();
	view->anim_timer = wl_event_loop_add_timer(
		wl_display_get_event_loop(view->server->display), tick, view);
	tick(view);
}

void anim_cancel(struct ul_view *view) {
	if (view->anim_timer) {
		finish(view);
	}
}

bool anim_running(struct ul_view *view) {
	return view->anim_timer != NULL;
}

/* ---- ghosts: close, minimize and restore ---------------------------------
 *
 * A ghost is a static copy of a window's scene (its rects and the client's
 * last buffers, which stay locked while the copy holds them), so a window
 * can keep animating after the client has unmapped it or while the real
 * tree is hidden.
 *
 *   close     the open animation backwards: the content wipes up, the
 *             frame goes, the accent line shrinks back to the center
 *   minimize  the window shrinks into its WINDOWS entry on the rail (the
 *             rectangle the shell gives through foreign-toplevel) and fades
 *   restore   the same, backwards; the real window shows when it lands
 */

#define CLOSE_WIPE_MS 180
#define CLOSE_LINE_MS 120
#define MINIMIZE_MS 220

enum ghost_kind { GHOST_CLOSE, GHOST_MINIMIZE, GHOST_RESTORE };

struct ghost_elem {
	struct wlr_scene_node *node;
	struct wlr_box box;     /* relative to the view's content origin */
	bool content;           /* client surface (wiped on close) */
	float color[4];         /* rects */
	struct clipped_region clip; /* rects: cut-out (e.g. the frame's inside) */
	float opacity;          /* buffers */
	struct wlr_fbox src;    /* buffers: source box, never empty */
};

struct ul_ghost {
	struct wl_list link; /* ul_server.ghosts */
	struct ul_server *server;
	struct ul_view *view; /* restore only: shown when done; NULL if gone */
	enum ghost_kind kind;
	struct wlr_scene_tree *tree;
	struct ghost_elem *elems;
	size_t n, cap;
	int bufs_seen, bufs_copied, bufs_readback; /* diagnostics */
	struct wlr_scene_rect *line;
	struct wlr_box frame;  /* frame box relative to content origin */
	struct wlr_box target; /* layout coords: rail entry (minimize/restore) */
	int origin_x, origin_y; /* layout position of the content origin */
	int content_y, content_h;
	struct wl_event_source *timer;
	uint32_t start;
	bool pending;   /* snapshot waiting for the window to unmap */
	bool requested; /* taken when we asked the client to close */
};

/* Newest animation on top. The ghost layer sits above all windows: when a
 * window closes or minimizes, focus moves on and the next window is raised,
 * which would otherwise cover the animation (e.g. a maximized window). */
static void place_ghost(struct ul_ghost *g, struct ul_view *view) {
	wlr_scene_node_raise_to_top(&g->tree->node);
}

/* Motion on/off: ULTIMIT_ANIMATIONS=0 at start, then whatever the shell says (ipc "motion"). */
static int motion = -1; /* -1: not decided yet (read the environment) */

void anim_set_motion(bool on) {
	motion = on;
}

bool anim_motion(void) {
	if (motion < 0) {
		const char *env = getenv("ULTIMIT_ANIMATIONS");
		motion = !(env && strcmp(env, "0") == 0);
	}
	return motion;
}

static bool animations_enabled(void) {
	return anim_motion();
}

static bool no_input(struct wlr_scene_buffer *buffer, double *sx, double *sy) {
	return false;
}

static struct ghost_elem *ghost_add(struct ul_ghost *g) {
	if (g->n == g->cap) {
		g->cap = g->cap ? g->cap * 2 : 16;
		g->elems = realloc(g->elems, g->cap * sizeof(*g->elems));
	}
	struct ghost_elem *e = &g->elems[g->n++];
	memset(e, 0, sizeof(*e));
	return e;
}

/* Copy the enabled nodes under `tree` (offset ox, oy from the content
 * origin) into the ghost. */
static void ghost_copy(struct ul_ghost *g, struct ul_view *view, struct wlr_scene_tree *tree,
		int ox, int oy, bool content, struct wlr_scene_tree *content_tree) {
	struct wlr_scene_node *node;
	wl_list_for_each(node, &tree->children, link) {
		if (!node->enabled) continue;
		int x = ox + node->x, y = oy + node->y;
		if (node->type == WLR_SCENE_NODE_TREE) {
			struct wlr_scene_tree *sub = wlr_scene_tree_from_node(node);
			ghost_copy(g, view, sub, x, y, content || sub == content_tree, content_tree);
		} else if (node->type == WLR_SCENE_NODE_RECT) {
			struct wlr_scene_rect *r = wlr_scene_rect_from_node(node);
			if (r->width <= 0 || r->height <= 0) continue;
			struct wlr_scene_rect *copy = wlr_scene_rect_create(g->tree, r->width, r->height, r->color);
			wlr_scene_rect_set_backdrop_blur(copy, r->backdrop_blur);
			wlr_scene_rect_set_backdrop_blur_optimized(copy, r->backdrop_blur_optimized);
			copy->accepts_input = false;
			wlr_scene_rect_set_clipped_region(copy, r->clipped_region);
			struct ghost_elem *e = ghost_add(g);
			e->node = &copy->node;
			e->clip = r->clipped_region;
			e->box = (struct wlr_box){ x, y, r->width, r->height };
			e->content = content;
			memcpy(e->color, r->color, sizeof(e->color));
		} else if (node->type == WLR_SCENE_NODE_BUFFER) {
			struct wlr_scene_buffer *b = wlr_scene_buffer_from_node(node);
			/* wlroots lets go of a buffer once it's uploaded; our own
			 * titlebar can simply be drawn again. */
			struct wlr_buffer *buf = b->buffer, *fresh = NULL;
			g->bufs_seen++;
			if (!buf && b == view->deco.titlebar) {
				buf = fresh = decoration_titlebar_buffer(view);
			}
			/* Explicit-sync clients (Chromium on the GPU): the scene keeps
			 * only the texture once it's uploaded; read it back. The texture
			 * is in wlroots' private section (we pin our own wlroots/SceneFX). */
			if (!buf && b->WLR_PRIVATE.texture) {
				buf = fresh = buffer_from_texture(b->WLR_PRIVATE.texture);
				if (buf) g->bufs_readback++;
			}
			if (!buf) continue;
			struct wlr_scene_buffer *copy = wlr_scene_buffer_create(g->tree, buf);
			if (fresh) wlr_buffer_drop(fresh);
			if (!copy) continue;
			g->bufs_copied++;
			wlr_scene_buffer_set_backdrop_blur(copy, b->backdrop_blur);
			wlr_scene_buffer_set_backdrop_blur_optimized(copy, b->backdrop_blur_optimized);
			int w = b->dst_width > 0 ? b->dst_width : buf->width;
			int h = b->dst_height > 0 ? b->dst_height : buf->height;
			struct wlr_fbox src = b->src_box;
			if (wlr_fbox_empty(&src)) {
				src = (struct wlr_fbox){ 0, 0, buf->width, buf->height };
			}
			wlr_scene_buffer_set_transform(copy, b->transform);
			wlr_scene_buffer_set_corner_radius(copy, b->corner_radius, b->corners);
			wlr_scene_buffer_set_opacity(copy, b->opacity);
			copy->point_accepts_input = no_input;
			struct ghost_elem *e = ghost_add(g);
			e->node = &copy->node;
			e->box = (struct wlr_box){ x, y, w, h };
			e->content = content;
			e->opacity = b->opacity;
			e->src = src;
		}
		/* Shadows and blur markers aren't copied. */
	}
}

static void ghost_destroy(struct ul_ghost *g) {
	if (g->timer) {
		wl_event_source_remove(g->timer);
	}
	if (g->view) {
		if (g->view->ghost == g) g->view->ghost = NULL;
		if (g->view->closing == g) g->view->closing = NULL;
	}
	wl_list_remove(&g->link);
	wlr_scene_node_destroy(&g->tree->node);
	free(g->elems);
	free(g);
}

/* Place every element scaled by s around the frame's top-left, with the
 * frame's top-left at layout (fx, fy), faded to alpha a, and content cut
 * off below layout-relative y `cut` (content coords; INT_MAX = no cut). */
static void ghost_layout(struct ul_ghost *g, double fx, double fy, double s,
		double a, int cut, bool chrome, int frame_dy) {
	int frame_mid = g->frame.y + g->frame.height / 2;
	for (size_t i = 0; i < g->n; i++) {
		struct ghost_elem *e = &g->elems[i];
		if (!e->content && !chrome) {
			wlr_scene_node_set_enabled(e->node, false);
			continue;
		}
		int w = e->box.width, h = e->box.height;
		int ey = e->box.y;
		struct clipped_region clip = e->clip;
		double src_h = e->src.height;
		/* The frame collapses with the wiped content: the border shortens
		 * and whatever sits on the bottom edge (brackets) rides up with it. */
		if (!e->content && frame_dy > 0) {
			if (!wlr_box_empty(&clip.area)) {
				h -= frame_dy;
				clip.area.height -= frame_dy;
				if (clip.area.height < 0) clip.area.height = 0;
			} else if (e->box.y + e->box.height / 2 > frame_mid) {
				ey -= frame_dy;
			}
		}
		if (e->content && e->box.y + h > cut) {
			int vis = cut - e->box.y;
			if (vis <= 0) {
				wlr_scene_node_set_enabled(e->node, false);
				continue;
			}
			src_h = e->src.height * vis / h;
			h = vis;
		}
		wlr_scene_node_set_enabled(e->node, true);
		int x = (int)(fx + (e->box.x - g->frame.x) * s);
		int y = (int)(fy + (ey - g->frame.y) * s);
		int sw = (int)(w * s), sh = (int)(h * s);
		if (sw < 1) sw = 1;
		if (sh < 1) sh = 1;
		wlr_scene_node_set_position(e->node, x, y);
		if (e->node->type == WLR_SCENE_NODE_RECT) {
			struct wlr_scene_rect *r = wlr_scene_rect_from_node(e->node);
			wlr_scene_rect_set_size(r, sw, sh);
			if (!wlr_box_empty(&e->clip.area)) {
				struct clipped_region c = clip;
				c.area = (struct wlr_box){ (int)(c.area.x * s), (int)(c.area.y * s),
					(int)(c.area.width * s), (int)(c.area.height * s) };
				wlr_scene_rect_set_clipped_region(r, c);
			}
			float c[4] = { e->color[0] * a, e->color[1] * a, e->color[2] * a, e->color[3] * a };
			wlr_scene_rect_set_color(r, c); /* premultiplied */
		} else {
			struct wlr_scene_buffer *b = wlr_scene_buffer_from_node(e->node);
			struct wlr_fbox src = e->src;
			src.height = src_h;
			wlr_scene_buffer_set_source_box(b, &src);
			wlr_scene_buffer_set_dest_size(b, sw, sh);
			wlr_scene_buffer_set_opacity(b, e->opacity * a);
		}
	}
}

#define CLOSE_REQUEST_WAIT_MS 3000

static int ghost_tick(void *data) {
	struct ul_ghost *g = data;
	if (g->pending) {
		/* A close request the client didn't act on (e.g. "Leave site?"). */
		ghost_destroy(g);
		return 0;
	}
	uint32_t elapsed = now_ms() - g->start;
	double fx0 = g->origin_x + g->frame.x, fy0 = g->origin_y + g->frame.y;

	if (g->kind == GHOST_CLOSE) {
		int fw = g->frame.width;
		if (elapsed < CLOSE_WIPE_MS) {
			double p = ease(elapsed / (double)CLOSE_WIPE_MS);
			int removed = (int)(g->content_h * p);
			int cut = g->content_y + g->content_h - removed;
			ghost_layout(g, fx0, fy0, 1, 1, cut, true, removed);
		} else if (elapsed < CLOSE_WIPE_MS + CLOSE_LINE_MS) {
			double p = ease((elapsed - CLOSE_WIPE_MS) / (double)CLOSE_LINE_MS);
			ghost_layout(g, fx0, fy0, 1, 1, INT_MIN / 2, false, 0);
			int w = (int)(fw * (1 - p));
			if (w < 2) w = 2;
			wlr_scene_rect_set_size(g->line, w, UL_BRACKET_W);
			wlr_scene_node_set_position(&g->line->node, (int)fx0 + (fw - w) / 2, (int)fy0);
			wlr_scene_node_set_enabled(&g->line->node, true);
		} else {
			ghost_destroy(g);
			return 0;
		}
	} else {
		if (elapsed >= MINIMIZE_MS) {
			struct ul_view *view = g->view;
			ghost_destroy(g);
			if (view && !view->minimized) {
				wlr_scene_node_set_enabled(&view->tree->node, true);
			}
			return 0;
		}
		double t = elapsed / (double)MINIMIZE_MS;
		double p = g->kind == GHOST_MINIMIZE ? ease(t) : 1 - ease(t);
		/* Uniform scale that fits the frame into the target. */
		double sx = g->target.width / (double)g->frame.width;
		double sy = g->target.height / (double)g->frame.height;
		double se = sx < sy ? sx : sy;
		double s = 1 + (se - 1) * p;
		double tx = g->target.x + (g->target.width - g->frame.width * se) / 2;
		double ty = g->target.y + (g->target.height - g->frame.height * se) / 2;
		double a = 1 - p * p;
		ghost_layout(g, fx0 + (tx - fx0) * p, fy0 + (ty - fy0) * p, s, a, INT_MAX, true, 0);
	}
	wl_event_source_timer_update(g->timer, TICK_MS);
	return 0;
}

static struct ul_ghost *ghost_create(struct ul_view *view, enum ghost_kind kind) {
	struct ul_server *server = view->server;
	struct ul_ghost *g = calloc(1, sizeof(*g));
	g->server = server;
	g->kind = kind;
	g->tree = wlr_scene_tree_create(server->layers[UL_LAYER_GHOSTS]);
	ghost_copy(g, view, view->tree, 0, 0, false, view->content);
	int bar = view->ssd ? UL_TITLEBAR_H : 0;
	g->frame = (struct wlr_box){ -UL_BORDER, -bar - UL_BORDER,
		view->width + 2 * UL_BORDER, view->height + bar + 2 * UL_BORDER };
	struct wlr_box geo = view_geometry_offset(view);
	/* The visible content starts at the content node's offset plus the
	 * geometry offset, in view-tree coordinates (as elem boxes are). */
	g->content_y = view->content->node.y + geo.y;
	g->content_h = view->height;
	g->origin_x = view->x;
	g->origin_y = view->y;
	g->line = wlr_scene_rect_create(g->tree, 2, UL_BRACKET_W, server->skin.accent);
	g->line->accepts_input = false;
	wlr_scene_node_set_enabled(&g->line->node, false);
	wl_list_insert(&server->ghosts, &g->link);
	wlr_log(WLR_DEBUG, "anim: ghost kind=%d view=%u elems=%zu buffers seen=%d copied=%d readback=%d",
		kind, view->id, g->n, g->bufs_seen, g->bufs_copied, g->bufs_readback);
	g->start = now_ms();
	g->timer = wl_event_loop_add_timer(wl_display_get_event_loop(server->display), ghost_tick, g);
	return g;
}

static bool can_close_anim(struct ul_view *view) {
	return animations_enabled() && !view->fullscreen && !view->minimized &&
		view->tree->node.enabled && view->content && !view->ghost;
}

/* By the time a surface unmaps, its buffer is already gone. So when a
 * mapped window commits "no buffer" (which unmaps it), snapshot it first;
 * the snapshot plays on unmap, or is dropped if the window lives on. */
static void handle_client_commit(struct wl_listener *listener, void *data) {
	struct ul_view *view = wl_container_of(listener, view, client_commit);
	struct wlr_surface *surface = view_surface(view);
	if (!surface || !(surface->pending.committed & WLR_SURFACE_STATE_BUFFER)) {
		return;
	}
	if (surface->pending.buffer == NULL) {
		if (!view->closing && view->mapped && can_close_anim(view)) {
			struct ul_ghost *g = ghost_create(view, GHOST_CLOSE);
			wlr_scene_node_set_enabled(&g->tree->node, false);
			g->view = view;
			g->pending = true;
			view->closing = g;
		}
	} else if (view->closing && !view->closing->requested) {
		ghost_destroy(view->closing);
	}
}

/* Some clients (Chromium) never detach the main surface's buffer before
 * their toplevel goes; by unmap their content is gone. So when we ask a
 * window to close, snapshot it then, while it still shows. */
void anim_close_requested(struct ul_view *view) {
	if (view->closing || !view->mapped || !can_close_anim(view)) {
		return;
	}
	struct ul_ghost *g = ghost_create(view, GHOST_CLOSE);
	wlr_scene_node_set_enabled(&g->tree->node, false);
	g->view = view;
	g->pending = true;
	g->requested = true;
	view->closing = g;
	wl_event_source_timer_update(g->timer, CLOSE_REQUEST_WAIT_MS);
}

void anim_track_commits(struct ul_view *view, bool track) {
	struct wlr_surface *surface = view_surface(view);
	if (track && surface && !view->client_commit.link.next) {
		view->client_commit.notify = handle_client_commit;
		wl_signal_add(&surface->events.client_commit, &view->client_commit);
	} else if (!track && view->client_commit.link.next) {
		wl_list_remove(&view->client_commit.link);
		view->client_commit.link.next = NULL;
	}
}

/* Called on unmap, before the view's scene is hidden. */
void anim_close(struct ul_view *view) {
	wlr_log(WLR_DEBUG, "anim: close view=%u snapshot=%s can=%d enabled=%d min=%d fs=%d",
		view->id, view->closing ? (view->closing->requested ? "requested" : "commit") : "none",
		can_close_anim(view), view->tree->node.enabled, view->minimized, view->fullscreen);
	if (view->ghost) {
		ghost_destroy(view->ghost); /* a restore still in flight */
	}
	struct ul_ghost *g = view->closing;
	if (g) {
		view->closing = NULL;
		g->view = NULL;
		g->pending = false;
		/* The window may have moved since a close-request snapshot. */
		g->origin_x = view->x;
		g->origin_y = view->y;
		g->start = now_ms();
		wlr_scene_node_set_enabled(&g->tree->node, true);
	} else if (can_close_anim(view)) {
		g = ghost_create(view, GHOST_CLOSE);
	} else {
		return;
	}
	place_ghost(g, view);
	ghost_tick(g);
}

static bool target_box(struct ul_view *view, struct wlr_box *out) {
	if (view->has_rail_rect) {
		*out = view->rail_rect;
		return true;
	}
	/* No rail entry known: sink toward the bottom of the screen. */
	struct ul_output *output = output_at(view->server,
		view->x + view->width / 2.0, view->y + view->height / 2.0);
	if (!output) return false;
	*out = (struct wlr_box){ view->x + view->width / 2 - 40,
		output->full_area.y + output->full_area.height - 60, 80, 50 };
	return true;
}

/* Minimize (true) after the real tree was hidden, or restore (false)
 * with the real tree still hidden: the ghost shows it when it lands. */
void anim_minimize(struct ul_view *view, bool minimize) {
	wlr_log(WLR_DEBUG, "anim: %s view=%u rail_rect=%d", minimize ? "minimize" : "restore",
		view->id, view->has_rail_rect);
	if (view->ghost) {
		ghost_destroy(view->ghost);
	}
	struct wlr_box target;
	if (!animations_enabled() || view->fullscreen || !view->content ||
			!target_box(view, &target)) {
		if (!minimize) {
			wlr_scene_node_set_enabled(&view->tree->node, true);
		}
		return;
	}
	struct ul_ghost *g = ghost_create(view, minimize ? GHOST_MINIMIZE : GHOST_RESTORE);
	g->target = target;
	if (!minimize) {
		g->view = view;
		view->ghost = g;
	}
	place_ghost(g, view);
	ghost_tick(g);
}

void anim_view_destroyed(struct ul_view *view) {
	anim_track_commits(view, false);
	if (view->closing) {
		ghost_destroy(view->closing);
	}
	if (view->ghost) {
		view->ghost->view = NULL;
		view->ghost = NULL;
	}
}

void anim_finish_all(struct ul_server *server) {
	struct ul_ghost *g, *tmp;
	wl_list_for_each_safe(g, tmp, &server->ghosts, link) {
		ghost_destroy(g);
	}
}
