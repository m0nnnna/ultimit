/*
 * security.c: which clients see the privileged protocols.
 *
 * Typing as the user (virtual keyboard/pointer), reading the screen
 * (screencopy, export-dmabuf, image capture), reading the clipboard in the
 * background (data-control), drawing over everything and grabbing the
 * keyboard (layer-shell), locking the session, changing monitors and gamma,
 * and listing every window are for the desktop's own tools: the shell, the
 * screenshot and screen-share portal, wtype/wlrctl/grim, cliphist.
 *
 * Sandboxed apps (Flatpak) don't get them: they share the screen through the
 * portal and paste through the normal clipboard. A native app running as the
 * user can already read ~ and ptrace the user's processes, so hiding these
 * from it would only break tools without stopping anyone; the line is the
 * sandbox, as on Sway, KDE and GNOME.
 *
 * A client counts as sandboxed when it connected through a
 * wp_security_context_v1 socket (Flatpak 1.15+ makes one per app), or when
 * its process root holds /.flatpak-info (older Flatpak), or when its process
 * can't be looked at (fail closed).
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <wayland-server-core.h>
#include <wlr/types/wlr_security_context_v1.h>
#include <wlr/util/log.h>
#include "server.h"

static const char *const privileged[] = {
	"zwp_virtual_keyboard_manager_v1",
	"zwlr_virtual_pointer_manager_v1",
	"zwlr_screencopy_manager_v1",
	"zwlr_export_dmabuf_manager_v1",
	"ext_image_copy_capture_manager_v1",
	"ext_output_image_capture_source_manager_v1",
	"ext_foreign_toplevel_image_capture_source_manager_v1",
	"zwlr_data_control_manager_v1",
	"ext_data_control_manager_v1",
	"zwlr_output_manager_v1",
	"zwlr_gamma_control_manager_v1",
	"zwlr_layer_shell_v1",
	"ext_session_lock_manager_v1",
	"zwlr_foreign_toplevel_manager_v1",
	"ext_foreign_toplevel_list_v1",
	"ext_idle_notifier_v1",
	"zwp_input_method_manager_v2",
	"wp_security_context_manager_v1", /* no nesting a new context from inside one */
};

static struct wlr_security_context_manager_v1 *contexts;

bool security_client_sandboxed(const struct wl_client *client) {
	if (contexts && wlr_security_context_manager_v1_lookup_client(contexts, client)) {
		return true;
	}
	pid_t pid;
	wl_client_get_credentials((struct wl_client *)client, &pid, NULL, NULL);
	if (pid <= 0) {
		return true;
	}
	char path[64];
	snprintf(path, sizeof(path), "/proc/%d/root/.flatpak-info", pid);
	if (access(path, F_OK) == 0) {
		return true;
	}
	/* Root not reachable (another user, not dumpable): don't trust it. */
	snprintf(path, sizeof(path), "/proc/%d/root/", pid);
	return access(path, X_OK) != 0;
}

static bool is_privileged(const struct wl_global *global) {
	const char *name = wl_global_get_interface(global)->name;
	for (size_t i = 0; i < sizeof(privileged) / sizeof(privileged[0]); i++) {
		if (strcmp(name, privileged[i]) == 0) {
			return true;
		}
	}
	return false;
}

static bool global_filter(const struct wl_client *client, const struct wl_global *global,
		void *data) {
	if (!is_privileged(global)) {
		return true;
	}
	return !security_client_sandboxed(client);
}

void security_init(struct ul_server *server) {
	contexts = wlr_security_context_manager_v1_create(server->display);
	wl_display_set_global_filter(server->display, global_filter, server);
}
