# Ultimit "Shard" cursors

Xcursor themes for the Ultimit desktop, one per skin in `shell/Theme.qml`:
`UltimitCursor-Mine`, `UltimitCursor-Amber`, `UltimitCursor-Silver`, `UltimitCursor-Verdant`
(named to avoid clashing with the `Ultimit-<Skin>` icon themes). The accent colours (and the
list of skins) are read from `Theme.qml`, so the cursor follows Settings > Appearance; a skin
added there gets a cursor at the next login, and changing a skin's colours rebuilds them.

Design: faceted crystal-shard arrow, dark-glass fill, thin accent edge, one faint
facet line, 1 px near-black (#050607) outer outline for contrast on any background.
Everything is drawn as vector paths with pycairo at 24 (nominal), 32 and 48 px.
Wait/progress are animated 12-frame hex rings (60 ms/frame).

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
