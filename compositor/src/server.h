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
#include <wlr/types/wlr_ext_foreign_toplevel_list_v1.h>
#include <wlr/types/wlr_foreign_toplevel_management_v1.h>
#include <wlr/types/wlr_layer_shell_v1.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_output_management_v1.h>
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
#include <xkbcommon/xkbcommon.h>

/* Scene layers, bottom to top. The optimized blur node sits between
 * UL_LAYER_BOTTOM and UL_LAYER_VIEWS, so glass samples the wallpaper. */
enum ul_layer {
	UL_LAYER_BG,
	UL_LAYER_BOTTOM,
	UL_LAYER_VIEWS,
	UL_LAYER_GHOSTS, /* close/minimize animations: above windows, so focusing the
	                  * next window (and raising it) can't cover them */
	UL_LAYER_TOP,
	UL_LAYER_FULLSCREEN,
	UL_LAYER_OVERLAY,
	UL_LAYER_LOCK, /* lock screen; covers everything while locked */
	UL_LAYER_COUNT,
};

/* Window tiling (view.c): which half of the output a window is snapped to. */
enum ul_snap {
	UL_SNAP_NONE,
	UL_SNAP_LEFT,
	UL_SNAP_RIGHT,
};

/* What dropping a dragged window at the current pointer position would do. */
enum ul_snap_zone {
	UL_ZONE_NONE,
	UL_ZONE_LEFT,
	UL_ZONE_RIGHT,
	UL_ZONE_MAXIMIZE,
};

#define UL_SNAP_STEPS 3        /* widths cycled by repeating Super+Left/Right: 1/2, 1/3, 2/3 */
#define UL_SNAP_EDGE 6         /* px from the screen edge that arms drag-to-snap */
#define UL_ALTTAB_MAX 64
#define UL_ALTTAB_DELAY_MS 150 /* a quicker Alt+Tab never shows the overlay */
#define UL_DESKTOP_MAX 128

enum ul_cursor_mode {
	UL_CURSOR_PASSTHROUGH,
	UL_CURSOR_MOVE,
	UL_CURSOR_RESIZE,
};

/* Settings from ~/.config/ultimit/compositor.ini (config.c). */
struct ul_config {
	bool tap;
	bool natural_scroll;
	bool disable_while_typing;
	bool left_handed;
	double accel_speed; /* -1..1 */
	char layout[64];
	char variant[64];
	char options[128];
	int repeat_rate;
	int repeat_delay;
	bool numlock; /* Num Lock on when a keyboard is plugged in or at login */
};

/* One [connector] section of ~/.config/ultimit/displays.conf (config.c),
 * written by Settings > Display when the user presses Keep. */
struct ul_output_conf {
	bool enabled;
	int width, height;    /* 0: keep the preferred mode */
	double refresh_hz;    /* 0: best refresh for that size */
	double scale;         /* 0: leave alone */
	bool has_pos;
	int x, y;
	int transform;        /* enum wl_output_transform */
	bool adaptive_sync;
};

struct ul_pointer {
	struct wl_list link;
	struct wlr_input_device *device;
	struct wl_listener destroy;
};

struct wlr_session_lock_manager_v1;
struct wlr_session_lock_v1;
struct wlr_idle_notifier_v1;

/* Window chrome colors for the current skin (straight RGBA). Starts as Mine
 * (theme.h); the shell pushes its skin with the "skin" IPC command. */
struct ul_skin {
	float panel[4], panel_dim[4], fg[4], dim[4], line[4], line_strong[4];
	float accent[4], accent_dim[4], bad[4];
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
	struct wlr_output_manager_v1 *output_manager; /* wlr-output-management: wlr-randr, Settings */
	struct wl_listener output_apply;
	struct wl_listener output_test;
	struct wl_listener layout_change;

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
	struct wlr_ext_foreign_toplevel_list_v1 *ext_toplevel_list; /* what capture sources are made from */
	struct wlr_tearing_control_manager_v1 *tearing_control;

	struct wlr_xdg_activation_v1 *activation;
	struct wl_listener request_activate;

	struct wlr_xwayland *xwayland;
	struct wl_listener xwayland_ready;
	struct wl_listener new_xwayland_surface;

	struct wl_list views; /* ul_view.link, most recently focused first */
	struct wl_list ghosts; /* ul_ghost.link: close/minimize animations (anim.c) */
	struct wl_list unmanaged; /* ul_unmanaged.link: mapped override-redirect X11 windows */
	bool super_tap; /* Super pressed with nothing else since (input.c) */
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
	struct wl_listener new_virtual_keyboard;
	struct wl_listener new_virtual_pointer;
	struct wl_listener request_cursor;
	struct wl_listener request_set_selection;
	struct wl_listener request_set_primary_selection;
	struct wl_list keyboards;
	struct wl_list pointers; /* ul_pointer.link */
	struct ul_config config;

	enum ul_cursor_mode cursor_mode;
	struct ul_view *grabbed_view;
	double grab_x, grab_y;
	struct wlr_box grab_box;
	uint32_t resize_edges;
	bool restore_on_drag; /* grabbed a maximized/snapped window; restore once it moves */
	enum ul_snap_zone snap_zone;      /* drag-to-snap target under the pointer (input.c) */
	struct ul_output *snap_zone_output;
	struct wlr_scene_tree *snap_preview; /* translucent accent rectangle for the zone */
	struct wlr_scene_rect *snap_preview_rects[5]; /* fill + 4 edges */

	/* Alt+Tab switcher (alttab.c) */
	struct {
		bool active;
		bool shown;           /* overlay announced to the shell */
		uint32_t hold_mods;   /* the modifier(s) that must stay down */
		int count, index;
		unsigned ids[UL_ALTTAB_MAX]; /* view ids, most recently focused first */
		struct wl_event_source *timer;
	} alttab;

	/* Show desktop (Super+D): the windows it minimized, most recent first */
	unsigned desktop_ids[UL_DESKTOP_MAX];
	int desktop_n;
	double press_x, press_y;

	/* Lock and idle (lock.c) */
	struct wlr_session_lock_manager_v1 *lock_manager;
	struct wlr_session_lock_v1 *lock;
	bool locked;
	struct wlr_scene_rect *lock_cover;
	struct wl_listener new_lock;
	struct wl_listener lock_new_surface;
	struct wl_listener lock_unlock;
	struct wl_listener lock_destroy;
	struct wlr_idle_notifier_v1 *idle_notifier;
	struct wl_listener new_inhibitor;
	int idle_inhibitors;

	int ipc_fd;
	char ipc_path[108];
	unsigned next_view_id;

	struct ul_view *last_click_view;
	uint32_t last_click_msec;

	struct ul_skin skin;
	struct ul_view *hover_view; /* view whose titlebar button is under the cursor */
};

struct ul_output {
	struct wl_list link;
	struct ul_server *server;
	struct wlr_output *wlr_output;
	struct wlr_scene_output *scene_output;
	struct wlr_box full_area;   /* layout coordinates */
	struct wlr_box usable_area; /* full_area minus exclusive zones */
	bool vrr_always; /* user turned adaptive sync on; else only for fullscreen */
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
	struct wlr_scene_rect *sweep; /* focus sweep along the titlebar's bottom edge */
	struct wl_event_source *sweep_timer;
	uint32_t sweep_start;
	int button_x[3]; /* left edge of minimize, maximize, close, in titlebar coords */
	int button_w[3];
	/* What the titlebar buffer was last drawn with, to skip redundant redraws. */
	int drawn_width;
	bool drawn_focused;
	int drawn_hover;
	char *drawn_title;
	int hover;       /* titlebar button under the cursor: 0..2, or -1 */
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

struct ul_ghost;
struct ul_capture_source;

struct ul_view {
	struct wl_list link;
	struct ul_server *server;
	enum ul_view_type type;
	unsigned id; /* stable handle for ultimitctl */
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
	int geo_x, geo_y;  /* last seen xdg geometry offset (invisible margins) */
	struct wlr_box saved; /* content box before maximize/snap/fullscreen */
	enum ul_snap snapped;
	int snap_step;        /* index into the 1/2, 1/3, 2/3 width cycle */

	struct wl_event_source *anim_timer;
	uint32_t anim_start;
	struct ul_ghost *ghost;    /* restore animation in flight */
	struct ul_ghost *closing;  /* snapshot taken when the client dropped its buffer */
	struct wl_listener client_commit;
	bool has_rail_rect;        /* the shell told us where our rail entry is */
	struct wlr_box rail_rect;  /* layout coords */

	struct wlr_xdg_toplevel_decoration_v1 *xdg_decoration;
	struct wl_listener decoration_request_mode;
	struct wl_listener decoration_destroy;

	struct wlr_foreign_toplevel_handle_v1 *foreign;
	struct wl_listener foreign_activate;
	struct wl_listener foreign_close;
	struct wl_listener foreign_minimize;
	struct wl_listener foreign_maximize;
	struct wl_listener foreign_fullscreen;
	struct wl_listener foreign_set_rectangle;
	struct wlr_ext_foreign_toplevel_handle_v1 *ext_foreign; /* ext-foreign-toplevel-list handle; data = view */
	struct ul_capture_source *capture; /* window capture source, made on demand (capture.c) */
	struct wl_listener set_override_redirect; /* xwayland.c */

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

/* config.c */
void xwayland_restack_unmanaged(struct ul_server *server);
bool xwayland_focus_unmanaged(struct ul_server *server, struct wlr_surface *surface);
bool input_set_cursor_theme(struct ul_server *server, const char *name, int size);
void config_load(struct ul_server *server);
void config_reload(struct ul_server *server);
void config_apply_pointer(struct ul_server *server, struct wlr_input_device *device);
void config_apply_keyboard(struct ul_server *server, struct wlr_keyboard *keyboard);
bool config_output_lookup(const char *name, struct ul_output_conf *out);

/* lock.c */
void lock_init(struct ul_server *server);
void lock_finish(struct ul_server *server);
void lock_arrange(struct ul_server *server);
void idle_activity(struct ul_server *server);
void idle_update_inhibit(struct ul_server *server);

struct out;
/* keys.c: the keybinding table */
bool keys_handle(struct ul_server *server, uint32_t mods, xkb_keysym_t sym);
void keys_write_json(struct out *o);
void keys_super_tap(struct ul_server *server);

/* alttab.c */
bool alttab_active(struct ul_server *server);
void alttab_step(struct ul_server *server, uint32_t mods, int dir);
void alttab_modifiers(struct ul_server *server, uint32_t mods);
bool alttab_key(struct ul_server *server, xkb_keysym_t sym);
void alttab_cancel(struct ul_server *server);
void alttab_view_gone(struct ul_server *server, unsigned id);

/* ipc.c */
void ipc_broadcast(const char *line);
void ipc_emit_alttab(struct ul_server *server, const char *action);
void ipc_init(struct ul_server *server, const char *wayland_socket);
void ipc_finish(struct ul_server *server);

/* main.c */
void server_spawn(const char *cmd);

/* output.c */
void output_init(struct ul_server *server);
void output_finish(struct ul_server *server);
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
void input_reapply_keyboards(struct ul_server *server);
void input_focus_layer(struct ul_server *server, struct wlr_layer_surface_v1 *layer_surface);
void input_test_drag(struct ul_server *server, struct ul_view *view, int x, int y, bool release);
void input_snap_preview_hide(struct ul_server *server);

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
void view_snap(struct ul_view *view, enum ul_snap side, int step);
void view_clear_snap(struct ul_view *view);
void view_restore(struct ul_view *view); /* un-snap or un-maximize */
void view_refit(struct ul_view *view);   /* re-fit a snapped/maximized window after the usable area changed */
struct wlr_box view_snap_frame(struct wlr_box area, enum ul_snap side, int step);
void view_clamp_into(struct ul_view *view, struct wlr_box area);
struct ul_view *view_by_id(struct ul_server *server, unsigned id);
void view_show_desktop(struct ul_server *server);
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
void anim_close(struct ul_view *view);
void anim_close_requested(struct ul_view *view);
struct wlr_buffer *decoration_titlebar_buffer(struct ul_view *view);
struct wlr_buffer *buffer_from_texture(struct wlr_texture *texture);
void anim_track_commits(struct ul_view *view, bool track);
void anim_minimize(struct ul_view *view, bool minimize);
void anim_view_destroyed(struct ul_view *view);
void anim_finish_all(struct ul_server *server);

/* decoration.c */
void decoration_create(struct ul_view *view);
void decoration_update(struct ul_view *view);
enum ul_titlebar_hit decoration_hit(struct ul_view *view, double lx, double ly);
void skin_init(struct ul_skin *skin);
bool skin_parse(struct ul_skin *skin, const char *args);
void decoration_restyle_all(struct ul_server *server);
void decoration_set_hover(struct ul_server *server, struct ul_view *view, int button);
void decoration_focus_sweep(struct ul_view *view);
void decoration_finish(struct ul_view *view);

/* capture.c */
void capture_init(struct ul_server *server);
void capture_view_commit(struct ul_view *view);
void capture_view_destroy(struct ul_view *view);
void capture_output_frame(struct ul_server *server);

/* xdg.c */
void xdg_init(struct ul_server *server);
bool xdg_kde_wants_ssd(struct ul_server *server, struct wlr_surface *surface);

/* xwayland.c */
void xwayland_init(struct ul_server *server);

#endif
