# Ultimit cursors (Izy and Shard)

Xcursor themes for the Ultimit desktop, one per skin in `shell/Theme.qml`:
`UltimitCursor-Mine`, `UltimitCursor-Amber`, `UltimitCursor-Silver`, `UltimitCursor-Verdant`
(named to avoid clashing with the `Ultimit-<Skin>` icon themes). The accent colours (and the
list of skins) are read from `Theme.qml`, so the cursor follows Settings > Appearance; a skin
added there gets a cursor at the next login, and changing a skin's colours rebuilds them.

Design: the desktop's own language rather than a classic pointer. Solid shapes are two-tone
crystal shards like the wallpaper's (lit face in the skin's accent, shadow face sunk toward its
panel colour); everything else is accent hairlines, chamfered chips (badges) and corner brackets
(grab), with hex rings for wait/progress and not-allowed. No cartoon hands: the link pointer is an
upright shard with a tap burst over its tip (the hotspot), so it is not mistaken for the arrow.
Badges (copy, alias, no-drop, help, context menu, dnd-move) are chips big enough to read at 24 px.
One outline in the skin's contrast colour (near-black, white on Silver) keeps them readable on
white and grey. Drawn as vector paths with pycairo at 24 (nominal), 32, 36, 48 and 64 px (so
1.5x and HiDPI scales get a drawn size, not a scaled one); wait/progress are animated 12-frame hex
rings (60 ms/frame) with one bright segment running round.

Default style, **Izy** (Settings > Appearance > Mouse cursor, `"cursorStyle": "izy"` in
shell.json, or `--style izy`; `"shard"` picks the Shard set above). A white dart with a thin rim and a
wedge in the notch in the skin's accent, plain accent badges beside it (link chain, ?, +, ⊘,
square, ...) instead of chips, and dashed round rings for wait/progress. The other cursors keep
their shapes, drawn white with an accent rim. Everything has the dark outline, on every skin;
where the accent is too dark to read on a dark window (Silver) the hairlines are white.

Coverage: all CSS cursor-shape-v1 names (files) plus X11 and hash-named aliases (symlinks).

Needs only `python3-cairo` (in `distro/packages-core.txt`); the Xcursor files are written by the
script itself, so `xcursorgen` (x11-apps, which removing GNOME can take away) is not needed.

- `build-cursors.py OUTDIR [--sheets DIR] [--skins Mine,Amber] [--theme Theme.qml] [--style izy|shard]` draws and writes the themes;
  `--sheets` also writes `contact-sheet-<Skin>.png` (24/48 px on dark, white, grey, amber;
  red pixel = hotspot).
- `install-cursors.sh [DEST]` builds every skin into DEST (default `~/.local/share/icons`);
  skips when `build-cursors.py`, `Theme.qml` and the accent and cursor style in shell.json are unchanged (sha256 stamp), so it is cheap at
  login. A failed build is logged to `~/.local/state/ultimit/cursors.log`.

Select with `XCURSOR_THEME=UltimitCursor-Mine XCURSOR_SIZE=24`.
