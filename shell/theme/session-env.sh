# Ultimit session theming environment. Source (`.`) from session/ultimit-session
# BEFORE starting the compositor so every app it launches inherits these.
# POSIX sh. Requires shell/theme/install-gtk-theme.sh to have been run once.
# Does not touch gsettings/dconf or ~/.config/gtk-*/gtk.css.

# Select the Ultimit theme for GTK3 and GTK4/libadwaita apps. NOTE: with
# GTK_THEME set, libadwaita does not load its own stylesheet; our gtk.css
# re-imports it from the libadwaita gresource and then overrides it.
export GTK_THEME=Ultimit

# Force libadwaita's dark colour scheme for these processes (the theme is a
# dark skin; this also makes @media (prefers-color-scheme: dark) rules match).
export ADW_DEBUG_COLOR_SCHEME=prefer-dark

# Note for the session script: apps started via D-Bus/systemd activation (e.g.
# nautilus launched by a portal) do not inherit this shell env; add
# GTK_THEME and ADW_DEBUG_COLOR_SCHEME to the dbus-update-activation-environment call.

# Icon theme for the Quickshell shell (DATA, launcher, window list). Without a Qt platform
# theme, Qt only searches "hicolor", and Quickshell reads QS_ICON_THEME once at startup.
# Preference order:
#   1. QS_ICON_THEME already set by the caller (kept as is)
#   2. Ultimit-<Skin> when that theme is installed (shell/theme/icons/install-icons.sh);
#      skin = $ULTIMIT_SKIN, else "skin" in ~/.config/ultimit/shell.json, else mine
#   3. the GTK setting (gsettings org.gnome.desktop.interface icon-theme), else Yaru-dark
# The shell itself re-skins its own icons live on a skin switch (Icons.qml); this variable only
# supplies the startup theme and the fallback for icons Ultimit does not draw.
if [ -z "$QS_ICON_THEME" ]; then
	_us_skin=${ULTIMIT_SKIN:-}
	if [ -z "$_us_skin" ] && [ -r "$HOME/.config/ultimit/shell.json" ]; then
		_us_skin=$(sed -n 's/.*"skin"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p' "$HOME/.config/ultimit/shell.json" | head -n 1)
	fi
	case "$_us_skin" in mine|amber|silver|verdant) ;; *) _us_skin=mine ;; esac
	_us_theme="Ultimit-$(printf %s "$_us_skin" | cut -c1 | tr a-z A-Z)$(printf %s "$_us_skin" | cut -c2-)"
	if [ -f "${XDG_DATA_HOME:-$HOME/.local/share}/icons/$_us_theme/index.theme" ] \
	   || [ -f "/usr/share/icons/$_us_theme/index.theme" ]; then
		export QS_ICON_THEME="$_us_theme"
	else
		QS_ICON_THEME=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
		export QS_ICON_THEME="${QS_ICON_THEME:-Yaru-dark}"
	fi
	unset _us_skin _us_theme
fi

# GTK apps read their icon theme from gsettings, not from the environment. The session script
# should run this once after sourcing (and the skin switcher again when the skin changes);
# this file deliberately does not touch gsettings/dconf:
#     gsettings set org.gnome.desktop.interface icon-theme "$QS_ICON_THEME"
# (Ultimit-<Skin> inherits Yaru / Adwaita / hicolor, so undrawn icons still resolve.)

# SSH agent: gcr's (from gcr4, not GNOME) listens here; GNOME used to export it.
if [ -z "$SSH_AUTH_SOCK" ] && [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gcr/ssh" ]; then
	export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gcr/ssh"
fi
