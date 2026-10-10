# Ultimit GTK theme

Restyles GTK3, GTK4/libadwaita, Electron (Wayland CSD) and Chromium (GTK theme
mode) windows so they sit next to Ultimit's own server-side titlebar
(`compositor/src/decoration.c`): glass-black panels, thin light lines, 34 px
titlebar with the title in Michroma, bracketed `[ _ ] [ □ ] [ × ]` window
buttons, accent corner bracket top-left, chamfered buttons, ice-blue accent (or
the skin's accent). **Only inside Ultimit sessions**: nothing global is touched
(no `~/.config/gtk-*/gtk.css`, no gsettings/dconf); a normal GNOME session never
selects the themes.

## Files
- `gtk/build-gtk.py`: stdlib generator. Palettes for the four skins (mirror of
  `Theme.qml`), helpers (chamfer, bracket, window-button SVGs), renders
  `gtk/templates/*` into complete theme dirs.
- `gtk/templates/gtk-3.0.css.in`, `gtk-4.0.css.in`: the two templates (`{{ expr }}`
  = python expression over the palette tokens).
- `gtk/templates/gtk-3.0-radius.css`, `gtk-4.0-radius.css`: generated lists of every
  selector GTK3-Adwaita / libadwaita gives a rounded corner, reset to 0 (appended last).
- `install-gtk-theme.sh`: builds + installs `Ultimit-Mine`, `Ultimit-Amber`,
  `Ultimit-Silver`, `Ultimit-Verdant` and `Ultimit` (alias of the current skin)
  into `${XDG_DATA_HOME:-~/.local/share}/themes`; seeds `gtk-3.0/4.0 settings.ini`
  `gtk-decoration-layout` if the key is missing. Idempotent.
- `session-env.sh`: `GTK_THEME=Ultimit-<Skin>` from `~/.config/ultimit/shell.json`
  (fallback Mine), `ADW_DEBUG_COLOR_SCHEME=prefer-light` for Silver else `prefer-dark`.

Generated output (`Ultimit-*/gtk-{3,4}.0/gtk.css`, `assets/btn-*.svg`) is not
committed; run the installer. Edit templates, not output.

## How it works
- GTK3: `@import` of the builtin Adwaita(-dark) contained CSS, then overrides.
  Headerbar/`.titlebar` is opaque panel colour (Chromium samples it), 34 px, bracket
  and bottom rule as background gradients. Window buttons: stock icon hidden, the
  bracketed glyph is the button's `background-image` (an SVG file in `assets/`;
  GTK3 does not load `data:` URIs and ignores `-gtk-icon-source` on a GtkImage
  that has an icon name). Chamfer: 1 px outline from four gradient edges plus two
  diagonal gradient corners painted in the surrounding colour.
- GTK4/libadwaita: with `GTK_THEME` set libadwaita skips its own stylesheet, so the
  theme `@import`s `resource:///org/gnome/Adwaita/styles/main-{dark,light}-yaru-default.css`
  and overrides it; named colours both as `@define-color` and `:root` vars.
  libadwaita resets window-control buttons with a 5-`:not()` selector, so ours are
  over-qualified (`WCB` in build-gtk.py).
- The compositor draws frame, corner brackets and shadow for CSD windows, so the
  client keeps no shadow and no invisible resize border.

## Chromium / Electron
Chromium (GTK mode) renders the `headerbar.titlebar`, window, button, entry, menu
and selection style contexts into pixels and samples them; all of those are
opaque solid colours here and selection is a solid accent mix. Electron apps (e.g.
the Claude desktop app) draw a GTK-themed CSD frame on Wayland from GTK3's
headerbar style, so the GTK3 theme is what they use.

## Regenerating the radius lists (after a libadwaita / GTK3 upgrade)
Extract the stylesheet with `gresource extract <lib> <path>` (libadwaita:
`/org/gnome/Adwaita/styles/default-dark-yaru-default.css`; GTK3:
`/org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css`), collect every rule whose
`border-radius` is not 0 (except `avatar`) and write `selector { border-radius: 0; }`.

## Known limitations
See the end of NOTES in the handoff; in short: titles are centred (GtkHeaderBar),
small-caps only via `text-transform` in GTK4, Ubuntu/Yaru-specific libadwaita import
path, running apps keep their skin until restarted.

## Icon theme
`theme/icons/` builds the four `Ultimit-<Skin>` freedesktop icon themes (see `theme/icons/README.md`);
`session-env.sh` selects `QS_ICON_THEME=Ultimit-<skin>` when installed, and the shell follows skin
switches live through `Icons.qml`.
