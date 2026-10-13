/*
 * decoration.c: Altimit-style window chrome. A translucent titlebar with the
 * accent square, the window title in the display face, the app id as a mono
 * subtitle, a rule that fades out toward the [ _ ] [ □ ] [ × ] buttons (which
 * light up under the cursor, close in red), a 1px frame, accent corner brackets top-left and
 * bottom-right, and a soft shadow. Client-side-decorated windows keep the
 * frame, brackets and shadow but get no titlebar.
 */

#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <cairo.h>
#include <drm_fourcc.h>
#include <wlr/render/wlr_texture.h>
#include <pango/pangocairo.h>
#include <scenefx/types/fx/clipped_region.h>
#include <scenefx/types/fx/corner_location.h>
#include <wlr/interfaces/wlr_buffer.h>
#include "server.h"
#include "theme.h"

static const float color_shadow[4] = UL_COLOR_SHADOW;

/* ---- skin ---------------------------------------------------------------- */

void skin_init(struct ul_skin *skin) {
	*skin = (struct ul_skin){
		.panel = UL_COLOR_PANEL, .panel_dim = UL_COLOR_PANEL_DIM,
		.fg = UL_COLOR_FG, .dim = UL_COLOR_DIM,
		.line = UL_COLOR_LINE, .line_strong = UL_COLOR_LINE_STRONG,
		.accent = UL_COLOR_ACCENT, .accent_dim = UL_COLOR_ACCENT_DIM,
		.bad = UL_COLOR_BAD,
	};
}

/* "#rrggbb" or "#rrggbbaa" (the # is optional). */
static bool parse_color(const char *s, float out[4]) {
	if (*s == '#') {
		s++;
	}
	size_t n = strlen(s);
	unsigned v[4] = { 0, 0, 0, 255 };
	if ((n != 6 && n != 8) || strspn(s, "0123456789abcdefABCDEF") != n) {
		return false;
	}
	for (size_t i = 0; i < n / 2; i++) {
		char hex[3] = { s[2 * i], s[2 * i + 1], 0 };
		v[i] = strtoul(hex, NULL, 16);
	}
	for (int i = 0; i < 4; i++) {
		out[i] = v[i] / 255.0f;
	}
	return true;
}

/* args: PANEL FG DIM LINE LINE_STRONG ACCENT BAD, as hex colors. The unfocused
 * panel and the dim accent are derived. Leaves *skin alone on bad input. */
bool skin_parse(struct ul_skin *skin, const char *args) {
	char tok[7][16] = {{0}};
	if (sscanf(args, "%15s %15s %15s %15s %15s %15s %15s",
			tok[0], tok[1], tok[2], tok[3], tok[4], tok[5], tok[6]) != 7) {
		return false;
	}
	struct ul_skin k;
	float *dst[7] = { k.panel, k.fg, k.dim, k.line, k.line_strong, k.accent, k.bad };
	for (int i = 0; i < 7; i++) {
		if (!parse_color(tok[i], dst[i])) {
			return false;
		}
	}
	memcpy(k.panel_dim, k.panel, sizeof(k.panel_dim));
	k.panel_dim[3] *= 0.875f;
	memcpy(k.accent_dim, k.accent, sizeof(k.accent_dim));
	k.accent_dim[3] = 0.22f;
	*skin = k;
	return true;
}

/* Redraw every window's chrome, e.g. after a skin change. */
void decoration_restyle_all(struct ul_server *server) {
	struct ul_view *view;
	wl_list_for_each(view, &server->views, link) {
		view->deco.drawn_width = -1;
		decoration_update(view);
	}
}

/* Track which titlebar button the cursor is over (view NULL or button -1 for
 * none) and redraw the titlebars that changed. */
void decoration_set_hover(struct ul_server *server, struct ul_view *view, int button) {
	if (!view || button < 0) {
		view = NULL;
		button = -1;
	}
	struct ul_view *prev = server->hover_view;
	if (prev == view && (!view || view->deco.hover == button)) {
		return;
	}
	if (prev) {
		prev->deco.hover = -1;
		decoration_update(prev);
	}
	server->hover_view = view;
	if (view) {
		view->deco.hover = button;
		decoration_update(view);
	}
}

/* ---- a wlr_buffer backed by a cairo image surface ------------------------ */

struct cairo_buffer {
	struct wlr_buffer base;
	cairo_surface_t *surface;
};

static void cairo_buffer_destroy(struct wlr_buffer *wlr_buffer) {
	struct cairo_buffer *buffer = wl_container_of(wlr_buffer, buffer, base);
	cairo_surface_destroy(buffer->surface);
	free(buffer);
}

static bool cairo_buffer_begin_data_ptr_access(struct wlr_buffer *wlr_buffer,
		uint32_t flags, void **data, uint32_t *format, size_t *stride) {
	struct cairo_buffer *buffer = wl_container_of(wlr_buffer, buffer, base);
	if (flags & WLR_BUFFER_DATA_PTR_ACCESS_WRITE) {
		return false;
	}
	*data = cairo_image_surface_get_data(buffer->surface);
	*format = DRM_FORMAT_ARGB8888;
	*stride = cairo_image_surface_get_stride(buffer->surface);
	return true;
}

static void cairo_buffer_end_data_ptr_access(struct wlr_buffer *wlr_buffer) {
}

static const struct wlr_buffer_impl cairo_buffer_impl = {
	.destroy = cairo_buffer_destroy,
	.begin_data_ptr_access = cairo_buffer_begin_data_ptr_access,
	.end_data_ptr_access = cairo_buffer_end_data_ptr_access,
};

/* ---- titlebar drawing ---------------------------------------------------- */

static void set_source(cairo_t *cr, const float c[4]) {
	cairo_set_source_rgba(cr, c[0], c[1], c[2], c[3]);
}

static int text_width(PangoLayout *layout) {
	int w, h;
	pango_layout_get_pixel_size(layout, &w, &h);
	return w;
}

static void draw_text(cairo_t *cr, PangoLayout *layout, double x, int bar_h) {
	int w, h;
	pango_layout_get_pixel_size(layout, &w, &h);
	cairo_move_to(cr, x, (bar_h - h) / 2.0);
	pango_cairo_show_layout(cr, layout);
}

/* Copy a texture into a new CPU buffer (the caller drops it): for window
 * snapshots whose client buffer the scene has already let go of. */
struct wlr_buffer *buffer_from_texture(struct wlr_texture *texture) {
	if (!texture || texture->width <= 0 || texture->height <= 0) {
		return NULL;
	}
	cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32,
		texture->width, texture->height);
	if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
		cairo_surface_destroy(surface);
		return NULL;
	}
	cairo_surface_flush(surface);
	bool ok = wlr_texture_read_pixels(texture, &(struct wlr_texture_read_pixels_options){
		.data = cairo_image_surface_get_data(surface),
		.format = DRM_FORMAT_ARGB8888,
		.stride = cairo_image_surface_get_stride(surface),
	});
	if (!ok) {
		cairo_surface_destroy(surface);
		return NULL;
	}
	cairo_surface_mark_dirty(surface);
	struct cairo_buffer *buffer = calloc(1, sizeof(*buffer));
	buffer->surface = surface;
	wlr_buffer_init(&buffer->base, &cairo_buffer_impl, texture->width, texture->height);
	return &buffer->base;
}

static void set_letter_spacing(PangoLayout *layout, double px) {
	PangoAttrList *attrs = pango_attr_list_new();
	pango_attr_list_insert(attrs, pango_attr_letter_spacing_new((int)(px * PANGO_SCALE)));
	pango_layout_set_attributes(layout, attrs);
	pango_attr_list_unref(attrs);
}

/* Draw the titlebar into a new buffer (the caller drops it). Left to right:
 * accent square, title, the app id as a dim mono subtitle, a rule fading out
 * toward the buttons. */
struct wlr_buffer *decoration_titlebar_buffer(struct ul_view *view) {
	struct ul_decoration *deco = &view->deco;
	const struct ul_skin *k = &view->server->skin;
	int width = view->width + 2 * UL_BORDER;
	int height = UL_TITLEBAR_H;
	if (width <= 0) {
		return NULL;
	}
	bool focused = view->server->focused_view == view;

	cairo_surface_t *surface =
		cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
	cairo_t *cr = cairo_create(surface);

	cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
	set_source(cr, focused ? k->panel : k->panel_dim);
	cairo_paint(cr);
	cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

	/* Buttons, laid out from the right edge in equal cells. */
	PangoLayout *button = pango_cairo_create_layout(cr);
	PangoFontDescription *button_font = pango_font_description_from_string(UL_FONT_BUTTON);
	pango_layout_set_font_description(button, button_font);
	static const char *labels[3] = { "[ _ ]", "[ □ ]", "[ × ]" };
	int cell = UL_BUTTON_MIN_W;
	for (int i = 0; i < 3; i++) {
		pango_layout_set_text(button, labels[i], -1);
		int w = text_width(button) + 12;
		cell = w > cell ? w : cell;
	}
	int x = width - 6;
	for (int i = 2; i >= 0; i--) {
		x -= cell;
		deco->button_x[i] = x;
		deco->button_w[i] = cell;
		bool hot = deco->hover == i;
		if (hot) {
			const float *tint = i == 2 ? k->bad : k->fg;
			cairo_set_source_rgba(cr, tint[0], tint[1], tint[2], i == 2 ? 0.20 : 0.08);
			cairo_rectangle(cr, x, 5, cell, height - 10);
			cairo_fill(cr);
		}
		pango_layout_set_text(button, labels[i], -1);
		set_source(cr, hot ? (i == 2 ? k->bad : k->fg) : k->dim);
		draw_text(cr, button, x + (cell - text_width(button)) / 2.0, height);
	}
	int buttons_left = x;

	/* Accent square, as in the shell's window headers and labels. */
	const int sq = 6, pad = 14;
	set_source(cr, focused ? k->accent : k->dim);
	cairo_rectangle(cr, pad, (height - sq) / 2, sq, sq);
	cairo_fill(cr);
	int title_x = pad + sq + 10;

	/* Title. */
	PangoLayout *title = pango_cairo_create_layout(cr);
	PangoFontDescription *title_font = pango_font_description_from_string(UL_FONT_TITLE);
	pango_layout_set_font_description(title, title_font);
	set_letter_spacing(title, 0.8);
	pango_layout_set_text(title, view_title(view), -1);
	pango_layout_set_ellipsize(title, PANGO_ELLIPSIZE_END);
	int title_max = buttons_left - title_x - 40;
	int title_end = title_x;
	if (title_max > 0) {
		pango_layout_set_width(title, title_max * PANGO_SCALE);
		set_source(cr, focused ? k->fg : k->dim);
		draw_text(cr, title, title_x, height);
		title_end = title_x + text_width(title);
	}

	/* Subtitle: the app id in caps, when there is room and it adds something
	 * (every shell app is "org.quickshell", which says nothing). */
	PangoLayout *sub = pango_cairo_create_layout(cr);
	PangoFontDescription *sub_font = pango_font_description_from_string(UL_FONT_SUB);
	pango_layout_set_font_description(sub, sub_font);
	set_letter_spacing(sub, 1.8);
	const char *app = view_app_id(view);
	const char *dot = strrchr(app, '.'); /* org.gnome.Nautilus -> NAUTILUS */
	char *label = g_utf8_strup(dot && dot[1] ? dot + 1 : app, -1);
	int text_end = title_end;
	if (label[0] && g_ascii_strcasecmp(label, view_title(view)) != 0 &&
			strcmp(app, "org.quickshell") != 0) {
		pango_layout_set_text(sub, label, -1);
		int sw = text_width(sub);
		if (title_end + 14 + sw + 40 <= buttons_left) {
			set_source(cr, k->dim);
			draw_text(cr, sub, title_end + 14, height);
			text_end = title_end + 14 + sw;
		}
	}
	g_free(label);

	/* Rule from the end of the text, fading out before the buttons: accent
	 * on the focused window. */
	double rule_x0 = text_end + 12;
	double rule_x1 = buttons_left - 8;
	if (rule_x1 - rule_x0 > 10) {
		const float *c = focused ? k->accent : k->line_strong;
		double a = focused ? 0.65 : c[3];
		cairo_pattern_t *grad = cairo_pattern_create_linear(rule_x0, 0, rule_x1, 0);
		cairo_pattern_add_color_stop_rgba(grad, 0, c[0], c[1], c[2], a);
		cairo_pattern_add_color_stop_rgba(grad, 1, c[0], c[1], c[2], 0);
		cairo_set_source(cr, grad);
		cairo_rectangle(cr, rule_x0, height / 2, rule_x1 - rule_x0, 1);
		cairo_fill(cr);
		cairo_pattern_destroy(grad);
	}

	pango_font_description_free(title_font);
	pango_font_description_free(sub_font);
	pango_font_description_free(button_font);
	g_object_unref(title);
	g_object_unref(sub);
	g_object_unref(button);
	cairo_destroy(cr);
	cairo_surface_flush(surface);

	struct cairo_buffer *buffer = calloc(1, sizeof(*buffer));
	buffer->surface = surface;
	wlr_buffer_init(&buffer->base, &cairo_buffer_impl, width, height);
	return &buffer->base;
}

static void render_titlebar(struct ul_view *view) {
	struct wlr_buffer *buffer = decoration_titlebar_buffer(view);
	if (buffer) {
		wlr_scene_buffer_set_buffer(view->deco.titlebar, buffer);
		wlr_buffer_drop(buffer);
	}
}

/* ---- scene nodes --------------------------------------------------------- */

void decoration_create(struct ul_view *view) {
	struct ul_decoration *deco = &view->deco;
	deco->tree = wlr_scene_tree_create(view->tree);
	wlr_scene_node_lower_to_bottom(&deco->tree->node);

	deco->shadow = wlr_scene_shadow_create(deco->tree, 0, 0, 0,
		UL_SHADOW_SIGMA, color_shadow);
	const struct ul_skin *k = &view->server->skin;
	deco->hover = -1;
	deco->border = wlr_scene_rect_create(deco->tree, 0, 0, k->line);
	deco->titlebar = wlr_scene_buffer_create(deco->tree, NULL);
	wlr_scene_buffer_set_backdrop_blur(deco->titlebar, true);
	wlr_scene_buffer_set_backdrop_blur_optimized(deco->titlebar, true);
	for (int i = 0; i < 4; i++) {
		deco->brackets[i] = wlr_scene_rect_create(deco->tree, 0, 0, k->accent);
	}
	deco->line = wlr_scene_rect_create(deco->tree, 0, 0, k->accent);
	wlr_scene_node_set_enabled(&deco->line->node, false);
	deco->sweep = wlr_scene_rect_create(deco->tree, 0, 0, k->accent);
	wlr_scene_node_set_enabled(&deco->sweep->node, false);
}

void decoration_finish(struct ul_view *view) {
	if (view->deco.sweep_timer) {
		wl_event_source_remove(view->deco.sweep_timer);
		view->deco.sweep_timer = NULL;
	}
}

/* ---- focus sweep: a short accent segment runs along the bottom edge of the
 * titlebar when a window gains focus ---------------------------------------- */

#define SWEEP_MS 260
#define SWEEP_W  96

static void sweep_stop(struct ul_view *view) {
	struct ul_decoration *deco = &view->deco;
	if (deco->sweep_timer) {
		wl_event_source_remove(deco->sweep_timer);
		deco->sweep_timer = NULL;
	}
	wlr_scene_node_set_enabled(&deco->sweep->node, false);
}

static int sweep_tick(void *data) {
	struct ul_view *view = data;
	struct ul_decoration *deco = &view->deco;
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	uint32_t elapsed = (now.tv_sec * 1000 + now.tv_nsec / 1000000) - deco->sweep_start;
	if (elapsed >= SWEEP_MS || !view->ssd || !view->mapped || view->fullscreen ||
			anim_running(view) || view->server->focused_view != view) {
		sweep_stop(view);
		return 0;
	}
	double t = elapsed / (double)SWEEP_MS;
	t = 1 - (1 - t) * (1 - t) * (1 - t); /* ease out */
	int fw = view->width + 2 * UL_BORDER;
	int x0 = -UL_BORDER + (int)((fw + SWEEP_W) * t) - SWEEP_W;
	int x1 = x0 + SWEEP_W;
	x0 = x0 < -UL_BORDER ? -UL_BORDER : x0;
	x1 = x1 > fw - UL_BORDER ? fw - UL_BORDER : x1;
	const float *a = view->server->skin.accent;
	float fade = 1.0f - (float)(elapsed / (double)SWEEP_MS) * 0.6f;
	const float c[4] = { a[0], a[1], a[2], a[3] * fade };
	wlr_scene_rect_set_color(deco->sweep, c);
	wlr_scene_rect_set_size(deco->sweep, x1 > x0 ? x1 - x0 : 1, 1);
	wlr_scene_node_set_position(&deco->sweep->node, x0, -UL_BORDER - 1);
	wlr_scene_node_raise_to_top(&deco->sweep->node);
	wlr_scene_node_set_enabled(&deco->sweep->node, x1 > x0);
	wl_event_source_timer_update(deco->sweep_timer, 16);
	return 0;
}

void decoration_focus_sweep(struct ul_view *view) {
	struct ul_decoration *deco = &view->deco;
	if (!deco->sweep || !anim_motion() || !view->ssd || !view->mapped || view->fullscreen || anim_running(view)) {
		return;
	}
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	deco->sweep_start = now.tv_sec * 1000 + now.tv_nsec / 1000000;
	if (!deco->sweep_timer) {
		deco->sweep_timer = wl_event_loop_add_timer(
			wl_display_get_event_loop(view->server->display), sweep_tick, view);
	}
	sweep_tick(view);
}

/* Positions everything relative to the view's root tree, whose origin is the
 * client surface origin (the content box starts at the geometry offset). */
void decoration_update(struct ul_view *view) {
	struct ul_decoration *deco = &view->deco;
	if (!deco->tree) {
		return;
	}
	bool visible = view->mapped && !view->fullscreen;
	wlr_scene_node_set_enabled(&deco->tree->node, visible);
	if (!visible) {
		return;
	}

	const struct ul_skin *k = &view->server->skin;
	bool focused = view->server->focused_view == view;
	int bar = view->ssd ? UL_TITLEBAR_H : 0;

	/* Frame box: content plus titlebar plus the 1px border, relative to the
	 * view tree whose origin is the visible window's top-left. */
	int fx = -UL_BORDER;
	int fy = -bar - UL_BORDER;
	int fw = view->width + 2 * UL_BORDER;
	int fh = view->height + bar + 2 * UL_BORDER;

	wlr_scene_rect_set_size(deco->border, fw, fh);
	wlr_scene_node_set_position(&deco->border->node, fx, fy);
	wlr_scene_rect_set_color(deco->border, focused ? k->line_strong : k->line);
	wlr_scene_rect_set_clipped_region(deco->border, (struct clipped_region){
		.corner_radius = 0,
		.corners = CORNER_LOCATION_NONE,
		.area = { UL_BORDER, UL_BORDER, fw - 2 * UL_BORDER, fh - 2 * UL_BORDER },
	});

	int sigma = (int)UL_SHADOW_SIGMA;
	wlr_scene_shadow_set_size(deco->shadow, fw + 2 * sigma, fh + 2 * sigma);
	wlr_scene_node_set_position(&deco->shadow->node, fx - sigma, fy - sigma);
	wlr_scene_shadow_set_clipped_region(deco->shadow, (struct clipped_region){
		.corner_radius = 0,
		.corners = CORNER_LOCATION_NONE,
		.area = { sigma, sigma, fw, fh },
	});

	/* Brackets: top-left (horizontal, vertical), bottom-right (h, v). */
	const float *accent = focused ? k->accent : k->accent_dim;
	struct { int x, y, w, h; } b[4] = {
		{ fx, fy, UL_BRACKET_LEN, UL_BRACKET_W },
		{ fx, fy, UL_BRACKET_W, UL_BRACKET_LEN },
		{ fx + fw - UL_BRACKET_LEN, fy + fh - UL_BRACKET_W, UL_BRACKET_LEN, UL_BRACKET_W },
		{ fx + fw - UL_BRACKET_W, fy + fh - UL_BRACKET_LEN, UL_BRACKET_W, UL_BRACKET_LEN },
	};
	for (int i = 0; i < 4; i++) {
		wlr_scene_rect_set_size(deco->brackets[i], b[i].w, b[i].h);
		wlr_scene_node_set_position(&deco->brackets[i]->node, b[i].x, b[i].y);
		wlr_scene_rect_set_color(deco->brackets[i], accent);
	}
	wlr_scene_rect_set_color(deco->line, k->accent);

	wlr_scene_node_set_enabled(&deco->titlebar->node, view->ssd);
	if (view->ssd) {
		wlr_scene_node_set_position(&deco->titlebar->node, fx, fy);
		const char *title = view_title(view);
		if (deco->drawn_width != fw || deco->drawn_focused != focused ||
				deco->drawn_hover != deco->hover ||
				!deco->drawn_title || strcmp(deco->drawn_title, title) != 0) {
			render_titlebar(view);
			deco->drawn_width = fw;
			deco->drawn_focused = focused;
			deco->drawn_hover = deco->hover;
			free(deco->drawn_title);
			deco->drawn_title = strdup(title);
		}
	}
}

enum ul_titlebar_hit decoration_hit(struct ul_view *view, double lx, double ly) {
	if (!view->ssd || view->fullscreen || !view->mapped) {
		return UL_HIT_NONE;
	}
	double tx = lx - (view->x - UL_BORDER);
	double ty = ly - (view->y - UL_TITLEBAR_H - UL_BORDER);
	if (tx < 0 || ty < 0 || tx >= view->width + 2 * UL_BORDER || ty >= UL_TITLEBAR_H) {
		return UL_HIT_NONE;
	}
	static const enum ul_titlebar_hit hits[3] = {
		UL_HIT_MINIMIZE, UL_HIT_MAXIMIZE, UL_HIT_CLOSE,
	};
	for (int i = 0; i < 3; i++) {
		if (tx >= view->deco.button_x[i] &&
				tx < view->deco.button_x[i] + view->deco.button_w[i]) {
			return hits[i];
		}
	}
	return UL_HIT_TITLE;
}
