/*
 * config.c: user settings the compositor applies itself, read from
 * ~/.config/ultimit/compositor.ini (written by the Settings app) and
 * re-read on `ultimitctl reload`.
 *
 *   [pointer]                     [keyboard]
 *   tap = true                    layout = us
 *   natural_scroll = false        variant =
 *   accel_speed = 0.0             options =
 *   disable_while_typing = false  repeat_rate = 25
 *   left_handed = false           repeat_delay = 600
 *
 * Missing file or keys fall back to these defaults.
 */

#include <ctype.h>
#include <libinput.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wlr/backend/libinput.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/interfaces/wlr_keyboard.h>
#include <xkbcommon/xkbcommon.h>
#include "server.h"

static void config_path(char *path, size_t size, const char *file) {
	const char *xdg = getenv("XDG_CONFIG_HOME");
	if (xdg && *xdg) {
		snprintf(path, size, "%s/ultimit/%s", xdg, file);
	} else {
		snprintf(path, size, "%s/.config/ultimit/%s", getenv("HOME"), file);
	}
}

static void set_defaults(struct ul_config *c) {
	*c = (struct ul_config){
		.tap = true,
		.natural_scroll = false,
		.accel_speed = 0.0,
		/* Off by default: on this ELAN touchpad it blocked every tap and
		 * click, as if a key were always held. */
		.disable_while_typing = false,
		.left_handed = false,
		.repeat_rate = 25,
		.repeat_delay = 600,
		.numlock = true,
	};
	snprintf(c->layout, sizeof(c->layout), "us");
}

static char *trim(char *s) {
	while (isspace((unsigned char)*s)) s++;
	char *e = s + strlen(s);
	while (e > s && isspace((unsigned char)e[-1])) *--e = '\0';
	return s;
}

static bool parse_bool(const char *v) {
	return strcmp(v, "true") == 0 || strcmp(v, "1") == 0 || strcmp(v, "yes") == 0;
}

void config_load(struct ul_server *server) {
	struct ul_config *c = &server->config;
	set_defaults(c);

	char path[512];
	config_path(path, sizeof(path), "compositor.ini");
	FILE *f = fopen(path, "r");
	if (!f) {
		return;
	}
	char line[512], section[32] = "";
	while (fgets(line, sizeof(line), f)) {
		char *s = trim(line);
		if (*s == '\0' || *s == '#' || *s == ';') continue;
		if (*s == '[') {
			char *end = strchr(s, ']');
			if (end) {
				*end = '\0';
				snprintf(section, sizeof(section), "%s", s + 1);
			}
			continue;
		}
		char *eq = strchr(s, '=');
		if (!eq) continue;
		*eq = '\0';
		char *key = trim(s), *val = trim(eq + 1);
		if (strcmp(section, "pointer") == 0) {
			if (strcmp(key, "tap") == 0) c->tap = parse_bool(val);
			else if (strcmp(key, "natural_scroll") == 0) c->natural_scroll = parse_bool(val);
			else if (strcmp(key, "accel_speed") == 0) c->accel_speed = atof(val);
			else if (strcmp(key, "disable_while_typing") == 0) c->disable_while_typing = parse_bool(val);
			else if (strcmp(key, "left_handed") == 0) c->left_handed = parse_bool(val);
		} else if (strcmp(section, "keyboard") == 0) {
			if (strcmp(key, "layout") == 0) snprintf(c->layout, sizeof(c->layout), "%s", val);
			else if (strcmp(key, "variant") == 0) snprintf(c->variant, sizeof(c->variant), "%s", val);
			else if (strcmp(key, "options") == 0) snprintf(c->options, sizeof(c->options), "%s", val);
			else if (strcmp(key, "repeat_rate") == 0) c->repeat_rate = atoi(val);
			else if (strcmp(key, "repeat_delay") == 0) c->repeat_delay = atoi(val);
			else if (strcmp(key, "numlock") == 0) c->numlock = parse_bool(val);
		}
	}
	fclose(f);
	if (c->accel_speed < -1) c->accel_speed = -1;
	if (c->accel_speed > 1) c->accel_speed = 1;
}

void config_apply_pointer(struct ul_server *server, struct wlr_input_device *device) {
	if (!wlr_input_device_is_libinput(device)) {
		return; /* virtual or nested-backend pointers have no settings */
	}
	struct libinput_device *dev = wlr_libinput_get_device_handle(device);
	struct ul_config *c = &server->config;
	if (libinput_device_config_tap_get_finger_count(dev) > 0) {
		libinput_device_config_tap_set_enabled(dev,
			c->tap ? LIBINPUT_CONFIG_TAP_ENABLED : LIBINPUT_CONFIG_TAP_DISABLED);
	}
	if (libinput_device_config_scroll_has_natural_scroll(dev)) {
		libinput_device_config_scroll_set_natural_scroll_enabled(dev, c->natural_scroll);
	}
	if (libinput_device_config_accel_is_available(dev)) {
		libinput_device_config_accel_set_speed(dev, c->accel_speed);
	}
	if (libinput_device_config_dwt_is_available(dev)) {
		libinput_device_config_dwt_set_enabled(dev, c->disable_while_typing ?
			LIBINPUT_CONFIG_DWT_ENABLED : LIBINPUT_CONFIG_DWT_DISABLED);
	}
	if (libinput_device_config_left_handed_is_available(dev)) {
		libinput_device_config_left_handed_set(dev, c->left_handed);
	}
}

void config_apply_keyboard(struct ul_server *server, struct wlr_keyboard *keyboard) {
	struct ul_config *c = &server->config;
	struct xkb_rule_names names = {
		.layout = c->layout[0] ? c->layout : NULL,
		.variant = c->variant[0] ? c->variant : NULL,
		.options = c->options[0] ? c->options : NULL,
	};
	struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	struct xkb_keymap *keymap = xkb_keymap_new_from_names(context, &names,
		XKB_KEYMAP_COMPILE_NO_FLAGS);
	if (!keymap) {
		wlr_log(WLR_ERROR, "Bad keyboard layout '%s' (variant '%s'); using US",
			c->layout, c->variant);
		keymap = xkb_keymap_new_from_names(context, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS);
	}
	/* A new keymap resets the lock state: keep Caps/Num Lock across a
	 * reload, and start a new keyboard with Num Lock on (configurable). */
	bool fresh = keyboard->keymap == NULL;
	xkb_mod_mask_t locked = keyboard->modifiers.locked;
	wlr_keyboard_set_keymap(keyboard, keymap);
	xkb_mod_index_t num = xkb_keymap_mod_get_index(keymap, XKB_MOD_NAME_NUM);
	if (fresh) {
		locked = 0;
		if (c->numlock && num != XKB_MOD_INVALID) {
			locked |= 1u << num;
		}
	}
	if (locked) {
		wlr_keyboard_notify_modifiers(keyboard, keyboard->modifiers.depressed,
			keyboard->modifiers.latched, locked, keyboard->modifiers.group);
	}
	xkb_keymap_unref(keymap);
	xkb_context_unref(context);
	wlr_keyboard_set_repeat_info(keyboard, c->repeat_rate, c->repeat_delay);
}

/* Re-read the file and apply it to every connected device. */
void config_reload(struct ul_server *server) {
	config_load(server);
	struct ul_pointer *p;
	wl_list_for_each(p, &server->pointers, link) {
		config_apply_pointer(server, p->device);
	}
	input_reapply_keyboards(server);
	wlr_log(WLR_INFO, "Config reloaded (tap=%d natural_scroll=%d layout=%s)",
		server->config.tap, server->config.natural_scroll, server->config.layout);
}

/*
 * ~/.config/ultimit/displays.conf, one section per connector:
 *
 *   [eDP-1]
 *   enabled = true
 *   mode = 1920x1080@144.000    (the @Hz part is optional)
 *   scale = 1.00
 *   x = 0
 *   y = 0
 *   transform = normal          (90, 180, 270, flipped, flipped-90, ...)
 *   adaptive_sync = false
 *
 * Read when an output connects. Returns false if it has no section.
 */
static int parse_transform(const char *v) {
	static const char *names[] = {
		"normal", "90", "180", "270",
		"flipped", "flipped-90", "flipped-180", "flipped-270",
	};
	for (int i = 0; i < 8; i++) {
		if (strcmp(v, names[i]) == 0) return i; /* matches enum wl_output_transform */
	}
	return 0;
}

bool config_output_lookup(const char *name, struct ul_output_conf *out) {
	char path[512];
	config_path(path, sizeof(path), "displays.conf");
	FILE *f = fopen(path, "r");
	if (!f) {
		return false;
	}
	*out = (struct ul_output_conf){ .enabled = true };
	bool found = false, in_section = false;
	char line[512];
	while (fgets(line, sizeof(line), f)) {
		char *s = trim(line);
		char *comment = strpbrk(s, "#;");
		if (comment && comment != s) *comment = '\0';
		s = trim(s);
		if (*s == '\0' || *s == '#' || *s == ';') continue;
		if (*s == '[') {
			char *end = strchr(s, ']');
			if (end) *end = '\0';
			in_section = strcmp(s + 1, name) == 0;
			found |= in_section;
			continue;
		}
		if (!in_section) continue;
		char *eq = strchr(s, '=');
		if (!eq) continue;
		*eq = '\0';
		char *key = trim(s), *val = trim(eq + 1);
		if (strcmp(key, "enabled") == 0) out->enabled = parse_bool(val);
		else if (strcmp(key, "mode") == 0) {
			out->refresh_hz = 0;
			if (sscanf(val, "%dx%d@%lf", &out->width, &out->height, &out->refresh_hz) < 2) {
				out->width = out->height = 0;
			}
		}
		else if (strcmp(key, "scale") == 0) out->scale = atof(val);
		else if (strcmp(key, "x") == 0) { out->x = atoi(val); out->has_pos = true; }
		else if (strcmp(key, "y") == 0) { out->y = atoi(val); out->has_pos = true; }
		else if (strcmp(key, "transform") == 0) out->transform = parse_transform(val);
		else if (strcmp(key, "adaptive_sync") == 0) out->adaptive_sync = parse_bool(val);
	}
	fclose(f);
	if (out->scale < 0.25 || out->scale > 4) out->scale = 0;
	return found;
}
