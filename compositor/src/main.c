/*
 * Ultimit compositor. Started life as SceneFX's tinywl (CC0); grew a layer
 * shell, XWayland, server-side Altimit chrome and the protocols games and
 * the Quickshell-based shell need.
 *
 * Runs on real hardware from a TTY or display manager, or nested in a window
 * on an existing desktop for development (wlroots picks the backend).
 */

#include <getopt.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>
#include <scenefx/render/fx_renderer/fx_renderer.h>
#include <wlr/types/wlr_data_control_v1.h>
#include <wlr/types/wlr_data_device.h>
#include <wlr/types/wlr_export_dmabuf_v1.h>
#include <wlr/types/wlr_fractional_scale_v1.h>
#include <wlr/types/wlr_gamma_control_v1.h>
#include <wlr/types/wlr_linux_dmabuf_v1.h>
#include <wlr/types/wlr_linux_drm_syncobj_v1.h>
#include <wlr/types/wlr_presentation_time.h>
#include <wlr/types/wlr_primary_selection_v1.h>
#include <wlr/types/wlr_screencopy_v1.h>
#include <wlr/types/wlr_single_pixel_buffer_v1.h>
#include <wlr/types/wlr_subcompositor.h>
#include <wlr/types/wlr_viewporter.h>
#include <wlr/types/wlr_xdg_output_v1.h>
#include <wlr/util/log.h>
#include "server.h"
#include "theme.h"

void server_spawn(const char *cmd) {
	pid_t pid = fork();
	if (pid == 0) {
		/* Double fork so children are reparented and never become zombies. */
		setsid();
		if (fork() == 0) {
			execl("/bin/sh", "/bin/sh", "-c", cmd, (char *)NULL);
			_exit(127);
		}
		_exit(0);
	} else if (pid > 0) {
		waitpid(pid, NULL, 0);
	}
}

static void usage(const char *argv0) {
	printf("Usage: %s [-s command] [-d]\n"
		"  -s command  run a command once the compositor is up (e.g. the shell)\n"
		"  -d          debug logging\n", argv0);
}

static int handle_terminate(int signal, void *data) {
	/* Logout or kill: shut down cleanly so clients and XWayland exit too. */
	wl_display_terminate(data);
	return 0;
}

int main(int argc, char *argv[]) {
	const char *startup_cmd = NULL;
	enum wlr_log_importance log_level = WLR_INFO;
	int c;
	while ((c = getopt(argc, argv, "s:dh")) != -1) {
		switch (c) {
		case 's':
			startup_cmd = optarg;
			break;
		case 'd':
			log_level = WLR_DEBUG;
			break;
		default:
			usage(argv[0]);
			return c == 'h' ? 0 : 1;
		}
	}
	wlr_log_init(log_level, NULL);
	signal(SIGPIPE, SIG_IGN);

	struct ul_server server = {0};
	wl_list_init(&server.views);
	server.display = wl_display_create();
	server.backend = wlr_backend_autocreate(wl_display_get_event_loop(server.display),
		&server.session);
	if (!server.backend) {
		wlr_log(WLR_ERROR, "Failed to create backend");
		return 1;
	}

	server.renderer = fx_renderer_create(server.backend);
	if (!server.renderer) {
		wlr_log(WLR_ERROR, "Failed to create renderer");
		return 1;
	}
	wlr_renderer_init_wl_shm(server.renderer, server.display);
	server.allocator = wlr_allocator_autocreate(server.backend, server.renderer);
	if (!server.allocator) {
		wlr_log(WLR_ERROR, "Failed to create allocator");
		return 1;
	}

	server.compositor = wlr_compositor_create(server.display, 6, server.renderer);
	wlr_subcompositor_create(server.display);
	wlr_data_device_manager_create(server.display);
	wlr_primary_selection_v1_device_manager_create(server.display);
	wlr_data_control_manager_v1_create(server.display);

	config_load(&server);
	output_init(&server);

	server.scene = wlr_scene_create();
	server.scene_layout = wlr_scene_attach_output_layout(server.scene, server.output_layout);
	for (int i = 0; i < UL_LAYER_COUNT; i++) {
		server.layers[i] = wlr_scene_tree_create(&server.scene->tree);
	}
	/* Plain Mine black until the shell draws its wallpaper on top. */
	static const float backdrop[4] = UL_COLOR_BG;
	server.backdrop = wlr_scene_rect_create(server.layers[UL_LAYER_BG], 0, 0, backdrop);
	/* Everything below this node is what glass blurs. */
	server.blur = wlr_scene_optimized_blur_create(&server.scene->tree, 0, 0);
	wlr_scene_node_place_above(&server.blur->node, &server.layers[UL_LAYER_BOTTOM]->node);

	/* Buffer sharing and timing: the GPU path games and video players use. */
	if (wlr_renderer_get_texture_formats(server.renderer, WLR_BUFFER_CAP_DMABUF)) {
		struct wlr_linux_dmabuf_v1 *dmabuf =
			wlr_linux_dmabuf_v1_create_with_renderer(server.display, 5, server.renderer);
		wlr_scene_set_linux_dmabuf_v1(server.scene, dmabuf);
	}
	int drm_fd = wlr_renderer_get_drm_fd(server.renderer);
	if (drm_fd >= 0 && server.renderer->features.timeline &&
			server.backend->features.timeline) {
		/* Explicit sync: what the NVIDIA driver needs for tear-free Wayland. */
		wlr_linux_drm_syncobj_manager_v1_create(server.display, 1, drm_fd);
		wlr_log(WLR_INFO, "Explicit sync (linux-drm-syncobj-v1) enabled");
	}
	wlr_presentation_create(server.display, server.backend, 2);
	server.tearing_control = wlr_tearing_control_manager_v1_create(server.display, 1);
	wlr_viewporter_create(server.display);
	wlr_single_pixel_buffer_manager_v1_create(server.display);
	wlr_fractional_scale_manager_v1_create(server.display, 1);
	wlr_xdg_output_manager_v1_create(server.display, server.output_layout);
	wlr_screencopy_manager_v1_create(server.display);
	wlr_export_dmabuf_manager_v1_create(server.display);
	struct wlr_gamma_control_manager_v1 *gamma = wlr_gamma_control_manager_v1_create(server.display);
	wlr_scene_set_gamma_control_manager_v1(server.scene, gamma);
	server.foreign_toplevels = wlr_foreign_toplevel_manager_v1_create(server.display);

	xdg_init(&server);
	layer_init(&server);
	input_init(&server);
	lock_init(&server);
	xwayland_init(&server);

	struct wl_event_loop *loop = wl_display_get_event_loop(server.display);
	wl_event_loop_add_signal(loop, SIGTERM, handle_terminate, server.display);
	wl_event_loop_add_signal(loop, SIGINT, handle_terminate, server.display);

	const char *socket = wl_display_add_socket_auto(server.display);
	if (!socket) {
		wlr_backend_destroy(server.backend);
		return 1;
	}
	if (!wlr_backend_start(server.backend)) {
		wlr_backend_destroy(server.backend);
		wl_display_destroy(server.display);
		return 1;
	}

	setenv("WAYLAND_DISPLAY", socket, true);
	ipc_init(&server, socket);
	setenv("XDG_CURRENT_DESKTOP", "Ultimit", true);
	setenv("XDG_SESSION_DESKTOP", "ultimit", true);
	/* Prefer native Wayland in toolkits; games still go through XWayland
	 * unless they opt in. */
	setenv("QT_QPA_PLATFORM", "wayland;xcb", false);
	setenv("SDL_VIDEODRIVER", "wayland,x11", false);
	setenv("MOZ_ENABLE_WAYLAND", "1", false);
	setenv("ELECTRON_OZONE_PLATFORM_HINT", "auto", false);

	if (startup_cmd) {
		server_spawn(startup_cmd);
	}
	wlr_log(WLR_INFO, "Ultimit running on WAYLAND_DISPLAY=%s", socket);
	wl_display_run(server.display);

	ipc_finish(&server);
	lock_finish(&server);
	wl_display_destroy_clients(server.display);
	/* wlroots 0.19 asserts that nothing still listens to an object it
	 * destroys, so detach every server-level listener first. */
	struct wl_listener *listeners[] = {
		&server.new_output, &server.new_xdg_toplevel, &server.new_xdg_popup,
		&server.new_layer_surface, &server.new_decoration, &server.new_kde_decoration,
		&server.request_activate, &server.cursor_motion, &server.cursor_motion_absolute,
		&server.cursor_button, &server.cursor_axis, &server.cursor_frame,
		&server.request_set_shape, &server.new_constraint, &server.constraint_destroy,
		&server.new_input, &server.new_virtual_keyboard, &server.new_virtual_pointer,
		&server.request_cursor, &server.request_set_selection,
		&server.request_set_primary_selection,
	};
	for (size_t i = 0; i < sizeof(listeners) / sizeof(listeners[0]); i++) {
		wl_list_remove(&listeners[i]->link);
	}
	if (server.xwayland) {
		/* wlroots asserts nobody is still listening when XWayland goes away. */
		wl_list_remove(&server.xwayland_ready.link);
		wl_list_remove(&server.new_xwayland_surface.link);
		wlr_xwayland_destroy(server.xwayland);
	}
	wlr_scene_node_destroy(&server.scene->tree.node);
	wlr_xcursor_manager_destroy(server.cursor_mgr);
	wlr_cursor_destroy(server.cursor);
	wlr_allocator_destroy(server.allocator);
	wlr_renderer_destroy(server.renderer);
	wlr_backend_destroy(server.backend);
	wl_display_destroy(server.display);
	return 0;
}
