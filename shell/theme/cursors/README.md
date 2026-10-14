# Ultimit "Shard" cursors

Xcursor themes for the Ultimit desktop, one per skin in `shell/Theme.qml`:
`UltimitCursor-Mine`, `UltimitCursor-Amber`, `UltimitCursor-Silver`, `UltimitCursor-Verdant`
(named to avoid clashing with the `Ultimit-<Skin>` icon themes). The accent colours (and the
list of skins) are read from `Theme.qml`, so the cursor follows Settings > Appearance; a skin
added there gets a cursor at the next login, and changing a skin's colours rebuilds them.

Design: the desktop's own language rather than a classic pointer. Solid shapes are two-tone
crystal shards like the wallpaper's (lit face in the skin's accent, shadow face sunk toward its
panel colour); everything else is accent hairlines, chamfered chips (badges) and corner brackets
(grab), with hex rings for wait/progress and not-allowed. No cartoon hands: the link pointer is an
upright shard. One thin outline in the skin's contrast colour (near-black, white on Silver).
Drawn as vector paths with pycairo at 24 (nominal), 32 and 48 px; wait/progress are animated
12-frame hex rings (60 ms/frame).

Coverage: all CSS cursor-shape-v1 names (files) plus X11 and hash-named aliases (symlinks).

Needs only `python3-cairo` (in `distro/packages-core.txt`); the Xcursor files are written by the
script itself, so `xcursorgen` (x11-apps, which removing GNOME can take away) is not needed.

- `build-cursors.py OUTDIR [--sheets DIR] [--skins Mine,Amber] [--theme Theme.qml]` draws and writes the themes;
  `--sheets` also writes `contact-sheet-<Skin>.png` (24/48 px on dark, white, grey, amber;
  red pixel = hotspot).
- `install-cursors.sh [DEST]` builds every skin into DEST (default `~/.local/share/icons`);
  skips when `build-cursors.py` and `Theme.qml` are unchanged (sha256 stamp), so it is cheap at
  login. A failed build is logged to `~/.local/state/ultimit/cursors.log`.

Select with `XCURSOR_THEME=UltimitCursor-Mine XCURSOR_SIZE=24`.
