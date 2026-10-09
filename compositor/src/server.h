#ifndef ULTIMIT_SERVER_H
#define ULTIMIT_SERVER_H

#include <stdbool.h>
#include <wayland-server-core.h>
#include <scenefx/types/wlr_scene.h>
#include <wlr/backend.h>
#include <wlr/backend/session.h>
#include <wlr/render/allocator.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_foreign_toplevel_management_v1.h>
#include <wlr/types/wlr_layer_shell_v1.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_pointer_constraints_v1.h>
#include <wlr/types/wlr_relative_pointer_v1.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_server_decoration.h>
#include <wlr/types/wlr_tearing_control_v1.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/types/wlr_xdg_activation_v1.h>
#include <wlr/types/wlr_xdg_decoration_v1.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/util/log.h>
#include <wlr/xwayland/xwayland.h>

/* Scene layers, bottom to top. The optimized blur node sits between
 * UL_LAYER_BOTTOM and UL_LAYER_VIEWS, so glass samples the wallpaper. */
enum ul_layer {
	UL_LAYER_BG,
	UL_LAYER_BOTTOM,
	UL_LAYER_VIEWS,
	UL_LAYER_TOP,
	UL_LAYER_FULLSCREEN,
	UL_LAYER_OVERLAY,
	UL_LAYER_COUNT,
};

enum ul_cursor_mode {
	UL_CURSOR_PASSTHROUGH,
	UL_CURSOR_MOVE,
	UL_CURSOR_RESIZE,
};

struct ul_server {
	struct wl_display *display;
	struct wlr_backend *backend;
	struct wlr_session *session;
	struct wlr_renderer *renderer;
	struct wlr_allocator *allocator;
	struct wlr_compositor *compositor;

	struct wlr_scene *scene;
	struct wlr_scene_output_layout *scene_layout;
	struct wlr_scene_tree *layers[UL_LAYER_COUNT];
	struct wlr_scene_rect *backdrop;
	struct wlr_scene_optimized_blur *blur;

	struct wlr_output_layout *output_layout;
	struct wl_list outputs; /* ul_output.link */
	struct wl_listener new_output;

	struct wlr_xdg_shell *xdg_shell;
	struct wl_listener new_xdg_toplevel;
	struct wl_listener new_xdg_popup;

	struct wlr_layer_shell_v1 *layer_shell;
	struct wl_listener new_layer_surface;

	struct wlr_xdg_decoration_manager_v1 *decoration_manager;
	struct wl_listener new_decoration;
	/* KDE's older server-decoration protocol: what GTK3 apps (Firefox,
	 * many games' launchers) use to hand their titlebar to us. */
	struct wlr_server_decoration_manager *kde_decoration_manager;
	struct wl_listener new_kde_decoration;
	struct wl_list kde_decorations; /* ul_kde_decoration.link */

	struct wlr_foreign_toplevel_manager_v1 *foreign_toplevels;
	struct wlr_tearing_control_manager_v1 *tearing_control;

	struct wlr_xdg_activation_v1 *activation;
	struct wl_listener request_activate;

	struct wlr_xwayland *xwayland;
	struct wl_listener xwayland_ready;
	struct wl_listener new_xwayland_surface;

	struct wl_list views; /* ul_view.link, most recently focused first */
	struct ul_view *focused_view;
	struct wlr_layer_surface_v1 *focused_layer;

	struct wlr_cursor *cursor;
	struct wlr_xcursor_manager *cursor_mgr;
	struct wl_listener cursor_motion;
	struct wl_listener cursor_motion_absolute;
	struct wl_listener cursor_button;
	struct wl_listener cursor_axis;
	struct wl_listener cursor_frame;
	struct wl_listener request_set_shape;

	struct wlr_relative_pointer_manager_v1 *relative_pointer;
	struct wlr_pointer_constraints_v1 *pointer_constraints;
	struct wlr_pointer_constraint_v1 *active_constraint;
	struct wl_listener new_constraint;
	struct wl_listener constraint_destroy;

	struct wlr_seat *seat;
	struct wl_listener new_input;
	struct wl_listener request_cursor;
	struct wl_listener request_set_selection;
	struct wl_listener request_set_primary_selection;
	struct wl_list keyboards;

	enum ul_cursor_mode cursor_mode;
	struct ul_view *grabbed_view;
	double grab_x, grab_y;
	struct wlr_box grab_box;
	uint32_t resize_edges;

	struct ul_view *last_click_view;
	uint32_t last_click_msec;
};

struct ul_output {
	struct wl_list link;
	struct ul_server *server;
	struct wlr_output *wlr_output;
	struct wlr_scene_output *scene_output;
	struct wlr_box full_area;   /* layout coordinates */
	struct wlr_box usable_area; /* full_area minus exclusive zones */
	struct wl_list layer_surfaces[4]; /* ul_layer_surface.link, per zwlr layer */

	struct wl_listener frame;
	struct wl_listener request_state;
	struct wl_listener destroy;
};

struct ul_layer_surface {
	struct wl_list link;
	struct ul_server *server;
	struct ul_output *output;
	struct wlr_layer_surface_v1 *layer_surface;
	struct wlr_scene_layer_surface_v1 *scene;
	struct wlr_scene_tree *popups; /* above windows, follows the surface */
	bool mapped;

	struct wl_listener map;
	struct wl_listener unmap;
	struct wl_listener commit;
	struct wl_listener destroy;
};

/* Server-side window chrome. Lives in its own tree under the view, below
 * the client content. */
struct ul_decoration {
	struct wlr_scene_tree *tree;
	struct wlr_scene_shadow *shadow;
	struct wlr_scene_rect *border;
	struct wlr_scene_rect *brackets[4];
	struct wlr_scene_buffer *titlebar;
	struct wlr_scene_rect *line; /* open animation */
	int button_x[3]; /* left edge of minimize, maximize, close, in titlebar coords */
	int button_w[3];
};

enum ul_view_type {
	UL_VIEW_XDG,
	UL_VIEW_XWAYLAND,
};

enum ul_titlebar_hit {
	UL_HIT_NONE,
	UL_HIT_TITLE,
	UL_HIT_MINIMIZE,
	UL_HIT_MAXIMIZE,
	UL_HIT_CLOSE,
};

struct ul_view {
	struct wl_list link;
	struct ul_server *server;
	enum ul_view_type type;
	struct wlr_xdg_toplevel *xdg_toplevel;
	struct wlr_xwayland_surface *xwayland_surface;

	struct wlr_scene_tree *tree;    /* root; node.data points back to this view */
	struct wlr_scene_tree *content; /* client surfaces */
	struct ul_decoration deco;

	bool mapped;
	bool ssd; /* we draw the titlebar */
	bool maximized;
	bool fullscreen;
	bool minimized;
	int x, y;          /* layout position of the content's top-left */
	int width, height; /* content size */
	struct wlr_box saved; /* content box before maximize/fullscreen */

	struct wl_event_source *anim_timer;
	uint32_t anim_start;

	struct wlr_xdg_toplevel_decoration_v1 *xdg_decoration;
	struct wl_listener decoration_request_mode;
	struct wl_listener decoration_destroy;

	struct wlr_foreign_toplevel_handle_v1 *foreign;
	struct wl_listener foreign_activate;
	struct wl_listener foreign_close;
	struct wl_listener foreign_minimize;
	struct wl_listener foreign_maximize;
	struct wl_listener foreign_fullscreen;

	struct wl_listener map;
	struct wl_listener unmap;
	struct wl_listener commit;
	struct wl_listener destroy;
	struct wl_listener request_move;
	struct wl_listener request_resize;
	struct wl_listener request_maximize;
	struct wl_listener request_fullscreen;
	struct wl_listener request_minimize;
	struct wl_listener set_title;
	struct wl_listener set_app_id;

	/* XWayland only */
	struct wl_listener associate;
	struct wl_listener dissociate;
	struct wl_listener request_configure;
	struct wl_listener request_activate;
	struct wl_listener set_decorations;
	struct wl_listener override_redirect_map;
};

/* main.c */
void server_spawn(const char *cmd);

/* output.c */
void output_init(struct ul_server *server);
struct ul_output *output_at(struct ul_server *server, double lx, double ly);
struct ul_output *output_for_view(struct ul_view *view);
void output_arrange(struct ul_output *output);
void server_update_backdrop(struct ul_server *server);

/* layer.c */
void layer_init(struct ul_server *server);
void layer_arrange(struct ul_output *output);
struct wlr_scene_tree *layer_popup_parent(struct wlr_layer_surface_v1 *layer_surface,
	int *out_x, int *out_y, struct ul_output **out_output);

/* input.c */
void input_init(struct ul_server *server);
void input_update_pointer_focus(struct ul_server *server, uint32_t time_msec);
void input_focus_layer(struct ul_server *server, struct wlr_layer_surface_v1 *layer_surface);

/* view.c */
struct ul_view *view_from_node(struct wlr_scene_node *node);
struct wlr_surface *view_surface(struct ul_view *view);
struct wlr_box view_geometry_offset(struct ul_view *view);
const char *view_title(struct ul_view *view);
const char *view_app_id(struct ul_view *view);
void view_map(struct ul_view *view);
void view_unmap(struct ul_view *view);
void view_destroy(struct ul_view *view);
void view_focus(struct ul_view *view);
void view_focus_next(struct ul_server *server);
void view_set_position(struct ul_view *view, int x, int y);
void view_request_size(struct ul_view *view, int width, int height);
void view_update_size(struct ul_view *view, int width, int height);
void view_set_maximized(struct ul_view *view, bool maximized);
void view_set_fullscreen(struct ul_view *view, bool fullscreen);
void view_set_minimized(struct ul_view *view, bool minimized);
void view_close(struct ul_view *view);
void view_begin_interactive(struct ul_view *view, enum ul_cursor_mode mode, uint32_t edges);
void view_update_title(struct ul_view *view);
void view_set_ssd(struct ul_view *view, bool ssd);
void view_init_foreign(struct ul_view *view);
bool view_wants_tearing(struct ul_view *view);

/* anim.c */
void anim_open(struct ul_view *view);
void anim_cancel(struct ul_view *view);
bool anim_running(struct ul_view *view);

/* decoration.c */
void decoration_create(struct ul_view *view);
void decoration_update(struct ul_view *view);
enum ul_titlebar_hit decoration_hit(struct ul_view *view, double lx, double ly);

/* xdg.c */
void xdg_init(struct ul_server *server);
bool xdg_kde_wants_ssd(struct ul_server *server, struct wlr_surface *surface);

/* xwayland.c */
void xwayland_init(struct ul_server *server);

#endif
