/*
 * anim.c: the window open animation from the mockup. An accent line draws
 * outward from the center of the frame's top edge, then the frame appears
 * and the content wipes down from the top. Skipped for windows that map
 * fullscreen (games) and when ULTIMIT_ANIMATIONS=0.
 */

#include <stdlib.h>
#include <string.h>
#include <time.h>
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
	} else {
		finish(view);
		return 0;
	}
	wl_event_source_timer_update(view->anim_timer, TICK_MS);
	return 0;
}

void anim_open(struct ul_view *view) {
	const char *env = getenv("ULTIMIT_ANIMATIONS");
	if ((env && strcmp(env, "0") == 0) || view->fullscreen || !view->content) {
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
