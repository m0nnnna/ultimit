/*
 * decoration.c: Altimit-style window chrome. A translucent titlebar with the
 * window title in the display face, a rule that fades out toward the
 * [ _ ] [ □ ] [ × ] buttons, a 1px frame, accent corner brackets top-left and
 * bottom-right, and a soft shadow. Client-side-decorated windows keep the
 * frame, brackets and shadow but get no titlebar.
 */

#include <assert.h>
#include <stdlib.h>
#include <cairo.h>
#include <drm_fourcc.h>
#include <pango/pangocairo.h>
#include <scenefx/types/fx/clipped_region.h>
#include <scenefx/types/fx/corner_location.h>
#include <wlr/interfaces/wlr_buffer.h>
#include "server.h"
#include "theme.h"

static const float color_border[4] = UL_COLOR_LINE;
static const float color_border_focus[4] = UL_COLOR_LINE_STRONG;
static const float color_accent[4] = UL_COLOR_ACCENT;
static const float color_accent_dim[4] = UL_COLOR_ACCENT_DIM;
static const float color_shadow[4] = UL_COLOR_SHADOW;

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

static void render_titlebar(struct ul_view *view) {
	struct ul_decoration *deco = &view->deco;
	int width = view->width + 2 * UL_BORDER;
	int height = UL_TITLEBAR_H;
	if (width <= 0) {
		return;
	}
	bool focused = view->server->focused_view == view;

	cairo_surface_t *surface =
		cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
	cairo_t *cr = cairo_create(surface);

	const float panel[4] = UL_COLOR_PANEL;
	const float panel_dim[4] = UL_COLOR_PANEL_DIM;
	const float fg[4] = UL_COLOR_FG;
	const float dim[4] = UL_COLOR_DIM;
	const float line[4] = UL_COLOR_LINE_STRONG;

	cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
	set_source(cr, focused ? panel : panel_dim);
	cairo_paint(cr);
	cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

	/* Buttons, laid out from the right edge. */
	PangoLayout *button = pango_cairo_create_layout(cr);
	PangoFontDescription *button_font = pango_font_description_from_string(UL_FONT_BUTTON);
	pango_layout_set_font_description(button, button_font);
	static const char *labels[3] = { "[ _ ]", "[ □ ]", "[ × ]" };
	int x = width - 10;
	for (int i = 2; i >= 0; i--) {
		pango_layout_set_text(button, labels[i], -1);
		int w = text_width(button) + 8;
		x -= w;
		deco->button_x[i] = x;
		deco->button_w[i] = w;
		set_source(cr, dim);
		draw_text(cr, button, x + 4, height);
	}
	int buttons_left = x;

	/* Title. */
	PangoLayout *title = pango_cairo_create_layout(cr);
	PangoFontDescription *title_font = pango_font_description_from_string(UL_FONT_TITLE);
	pango_layout_set_font_description(title, title_font);
	pango_layout_set_text(title, view_title(view), -1);
	pango_layout_set_ellipsize(title, PANGO_ELLIPSIZE_END);
	int title_max = buttons_left - 16 - 40;
	if (title_max > 0) {
		pango_layout_set_width(title, title_max * PANGO_SCALE);
		set_source(cr, focused ? fg : dim);
		draw_text(cr, title, 16, height);
	}

	/* Rule from the end of the title, fading out before the buttons. */
	double rule_x0 = 16 + text_width(title) + 12;
	double rule_x1 = buttons_left - 12;
	if (rule_x1 - rule_x0 > 10) {
		cairo_pattern_t *grad = cairo_pattern_create_linear(rule_x0, 0, rule_x1, 0);
		cairo_pattern_add_color_stop_rgba(grad, 0, line[0], line[1], line[2], line[3]);
		cairo_pattern_add_color_stop_rgba(grad, 1, line[0], line[1], line[2], 0);
		cairo_set_source(cr, grad);
		cairo_rectangle(cr, rule_x0, height / 2, rule_x1 - rule_x0, 1);
		cairo_fill(cr);
		cairo_pattern_destroy(grad);
	}

	pango_font_description_free(title_font);
	pango_font_description_free(button_font);
	g_object_unref(title);
	g_object_unref(button);
	cairo_destroy(cr);
	cairo_surface_flush(surface);

	struct cairo_buffer *buffer = calloc(1, sizeof(*buffer));
	buffer->surface = surface;
	wlr_buffer_init(&buffer->base, &cairo_buffer_impl, width, height);
	wlr_scene_buffer_set_buffer(deco->titlebar, &buffer->base);
	wlr_buffer_drop(&buffer->base);
}

/* ---- scene nodes --------------------------------------------------------- */

void decoration_create(struct ul_view *view) {
	struct ul_decoration *deco = &view->deco;
	deco->tree = wlr_scene_tree_create(view->tree);
	wlr_scene_node_lower_to_bottom(&deco->tree->node);

	deco->shadow = wlr_scene_shadow_create(deco->tree, 0, 0, 0,
		UL_SHADOW_SIGMA, color_shadow);
	deco->border = wlr_scene_rect_create(deco->tree, 0, 0, color_border);
	deco->titlebar = wlr_scene_buffer_create(deco->tree, NULL);
	wlr_scene_buffer_set_backdrop_blur(deco->titlebar, true);
	wlr_scene_buffer_set_backdrop_blur_optimized(deco->titlebar, true);
	for (int i = 0; i < 4; i++) {
		deco->brackets[i] = wlr_scene_rect_create(deco->tree, 0, 0, color_accent);
	}
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

	bool focused = view->server->focused_view == view;
	struct wlr_box geo = view_geometry_offset(view);
	int bar = view->ssd ? UL_TITLEBAR_H : 0;

	/* Frame box: content plus titlebar plus the 1px border. */
	int fx = geo.x - UL_BORDER;
	int fy = geo.y - bar - UL_BORDER;
	int fw = view->width + 2 * UL_BORDER;
	int fh = view->height + bar + 2 * UL_BORDER;

	wlr_scene_rect_set_size(deco->border, fw, fh);
	wlr_scene_node_set_position(&deco->border->node, fx, fy);
	wlr_scene_rect_set_color(deco->border, focused ? color_border_focus : color_border);
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
	const float *accent = focused ? color_accent : color_accent_dim;
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

	wlr_scene_node_set_enabled(&deco->titlebar->node, view->ssd);
	if (view->ssd) {
		wlr_scene_node_set_position(&deco->titlebar->node, fx, fy);
		render_titlebar(view);
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
