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

# Icon theme for the Quickshell shell (DATA, launcher, window list). Without a
# Qt platform theme, Qt only searches "hicolor"; follow the GTK setting.
if [ -z "$QS_ICON_THEME" ]; then
	QS_ICON_THEME=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
	export QS_ICON_THEME="${QS_ICON_THEME:-Yaru-dark}"
fi

# SSH agent: gcr's (from gcr4, not GNOME) listens here; GNOME used to export it.
if [ -z "$SSH_AUTH_SOCK" ] && [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gcr/ssh" ]; then
	export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gcr/ssh"
fi
