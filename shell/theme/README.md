# Ultimit GTK theme

Restyles GTK4/libadwaita and GTK3 apps (headerbars, buttons, entries, lists,
popovers, switches, scrollbars) to the "Mine" skin of `docs/design/mockup.html`,
**only inside Ultimit sessions**. Nothing global is touched: no
`~/.config/gtk-{3,4}.0/gtk.css`, no gsettings/dconf. A normal GNOME session never
selects the theme, so it is unaffected.

## Files
- `gtk/Ultimit/gtk-4.0/gtk.css`, `gtk/Ultimit/gtk-3.0/gtk.css`, `gtk/Ultimit/index.theme`
- `install-gtk-theme.sh`: symlinks (or `--copy`) the theme to `~/.local/share/themes/Ultimit`. Idempotent.
- `session-env.sh`: `.`-source from the session script; exports `GTK_THEME=Ultimit` and `ADW_DEBUG_COLOR_SCHEME=prefer-dark`.

## Approach and why
Options evaluated:

1. **`GTK_THEME=Ultimit` + `~/.local/share/themes/Ultimit/gtk-4.0/gtk.css` (chosen).**
   Per-process env, no global config. Verified empirically on this machine
   (libadwaita 1.9.1 Ubuntu build, GTK 4.22.4): when `GTK_THEME` is set,
   libadwaita does **not** load its own stylesheet at all (a plain theme with one
   rule rendered an unstyled white window). So a theme must supply everything. Our
   `gtk.css` therefore starts with
   `@import url("resource:///org/gnome/Adwaita/styles/main-dark-yaru-default.css")`
   (libadwaita's stylesheet, which stays in its gresource even when not
   auto-loaded), then overrides it. Later rules at the same priority win, so
   widget selectors in our file beat the imported ones.
2. **libadwaita named colours / CSS variables** (`--window-bg-color`,
   `--headerbar-bg-color`, `--accent-bg-color`, ... and the `@define-color`
   twins). These only recolour; they cannot change radii, borders, fonts or the
   window controls. We use them (set in `:root` and via `@define-color`) so
   libadwaita's own derived colours follow the skin, and add widget rules for shape.
3. **`ADW_DEBUG_COLOR_SCHEME=prefer-dark`.** Forces dark per-process so
   `prefers-color-scheme: dark` blocks in the imported sheet match. Kept.
4. **`~/.config/gtk-4.0/gtk.css`** (the only no-env way to restyle libadwaita)
   or `XDG_CONFIG_HOME` redirection: rejected (global / breaks every app's config).
5. **GTK3: `GTK_THEME=Ultimit`** picks `gtk-3.0/gtk.css` the same way. GTK3 has no
   auto-loaded base theme under a custom name either, so we `@import` the
   built-in `resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css`
   and override. The `:dark` suffix is not needed (the theme is dark only).

## Skins
Edit only the token block at the top of each gtk.css (`@define-color u_*` plus
the `:root` variable block in GTK4; keep the two in sync). Amber/Silver/Verdant
= same block with the mockup's values.

## Verification (headless compositor)
GTK4 and GTK3 probe windows were rendered offscreen and inspected; no
"Theme parser error" / parsing warnings after the final edit.

## Known limitations
- Ubuntu-specific import path (`main-dark-yaru-default.css`): libadwaita is
  Yaru-patched here. On a stock libadwaita the file name would be `main-dark.css`.
- GTK CSS has no `clip-path`/chamfers, so buttons are square. Only the
  top-left accent corner bracket is drawn (on the headerbar); the bottom-right
  one is not possible since window content is opaque.
- Window control icons stay symbolic icons (can't render `[ _ ]` text via CSS);
  they are flat square buttons, close hover = danger colour.
- `text-transform` works in GTK4 but not GTK3 (subtitle uppercase only in GTK4).
- libadwaita apps that ship their own CSS (e.g. custom accent classes) may
  keep some rounded corners. GTK3 window top corners may remain slightly rounded.
- With `GTK_THEME` set, libadwaita may print a notice that it is not using its
  stylesheet; harmless.
- Apps started by D-Bus/systemd activation do not inherit the session shell env;
  export `GTK_THEME` and `ADW_DEBUG_COLOR_SCHEME` via `dbus-update-activation-environment`.

## Icon theme
`theme/icons/` builds the four `Ultimit-<Skin>` freedesktop icon themes (see `theme/icons/README.md`);
`session-env.sh` selects `QS_ICON_THEME=Ultimit-<skin>` when installed, and the shell follows skin
switches live through `Icons.qml`.
