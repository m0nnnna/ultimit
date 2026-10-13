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
 * ~/.config/ultimit/displays.conf, one section per monitor:
 *
 *   [eDP-1]
 *   id = BOE|0x0A1C|           (make|model|serial from the EDID; optional)
 *   enabled = true
 *   mode = 1920x1080@144.000    (the @Hz part is optional)
 *   scale = 1.00
 *   x = 0
 *   y = 0
 *   transform = normal          (90, 180, 270, flipped, flipped-90, ...)
 *   adaptive_sync = false
 *   primary = true              (the main display)
 *
 * Read when an output connects. A section whose id is this monitor wins wherever it is plugged
 * in (connector names move between cables, GPUs and boots); a section named after the connector
 * is used only if it has no id. Returns false if nothing matches.
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

bool config_output_lookup(const char *name, const char *id, struct ul_output_conf *out) {
	char path[512];
	config_path(path, sizeof(path), "displays.conf");
	FILE *f = fopen(path, "r");
	if (!f) {
		return false;
	}
	struct ul_output_conf cur = { .enabled = true }, by_name = { 0 };
	char cur_name[128] = "", cur_id[256] = "";
	bool in_section = false, have_id_match = false, have_name_match = false;
	char line[512];
	/* Decide about the section just read: is it this monitor? */
	#define SECTION_DONE() do { \
		if (in_section && id[0] && strcmp(cur_id, id) == 0) { *out = cur; have_id_match = true; } \
		else if (in_section && !cur_id[0] && strcmp(cur_name, name) == 0) { by_name = cur; have_name_match = true; } \
	} while (0)
	while (!have_id_match && fgets(line, sizeof(line), f)) {
		char *s = trim(line);
		char *comment = strpbrk(s, "#;");
		if (comment && comment != s) *comment = '\0';
		s = trim(s);
		if (*s == '\0' || *s == '#' || *s == ';') continue;
		if (*s == '[') {
			SECTION_DONE();
			char *end = strchr(s, ']');
			if (end) *end = '\0';
			snprintf(cur_name, sizeof(cur_name), "%s", s + 1);
			cur_id[0] = '\0';
			cur = (struct ul_output_conf){ .enabled = true };
			in_section = true;
			continue;
		}
		if (!in_section) continue;
		char *eq = strchr(s, '=');
		if (!eq) continue;
		*eq = '\0';
		char *key = trim(s), *val = trim(eq + 1);
		if (strcmp(key, "id") == 0) snprintf(cur_id, sizeof(cur_id), "%s", val);
		else if (strcmp(key, "enabled") == 0) cur.enabled = parse_bool(val);
		else if (strcmp(key, "mode") == 0) {
			cur.refresh_hz = 0;
			if (sscanf(val, "%dx%d@%lf", &cur.width, &cur.height, &cur.refresh_hz) < 2) {
				cur.width = cur.height = 0;
			}
		}
		else if (strcmp(key, "scale") == 0) cur.scale = atof(val);
		else if (strcmp(key, "x") == 0) { cur.x = atoi(val); cur.has_pos = true; }
		else if (strcmp(key, "y") == 0) { cur.y = atoi(val); cur.has_pos = true; }
		else if (strcmp(key, "transform") == 0) cur.transform = parse_transform(val);
		else if (strcmp(key, "adaptive_sync") == 0) cur.adaptive_sync = parse_bool(val);
		else if (strcmp(key, "primary") == 0) cur.primary = parse_bool(val);
	}
	if (!have_id_match) SECTION_DONE();
	#undef SECTION_DONE
	fclose(f);
	if (!have_id_match && have_name_match) *out = by_name;
	if (!have_id_match && !have_name_match) return false;
	if (out->scale < 0.25 || out->scale > 4) out->scale = 0;
	return true;
}
