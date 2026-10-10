# Ultimit "Shard" cursors

Xcursor themes for the Ultimit desktop, one per skin: `UltimitCursor-Mine`,
`UltimitCursor-Amber`, `UltimitCursor-Silver`, `UltimitCursor-Verdant`
(named to avoid clashing with the `Ultimit-<Skin>` icon themes).

Design: faceted crystal-shard arrow, dark-glass fill, thin accent edge, one faint
facet line, 1 px near-black (#050607) outer outline for contrast on any background.
Everything is drawn as vector paths with pycairo at 24 (nominal), 32 and 48 px.
Wait/progress are animated 12-frame hex rings (60 ms/frame).

Coverage: all CSS cursor-shape-v1 names (files) plus X11 and hash-named aliases (symlinks).

- `build-cursors.py OUTDIR [--sheets DIR] [--skins Mine,Amber]` draws + runs xcursorgen;
  `--sheets` also writes `contact-sheet-<Skin>.png` (24/48 px on dark, white, grey, amber;
  red pixel = hotspot).
- `install-cursors.sh [DEST]` builds all four into DEST (default `~/.local/share/icons`);
  skips when `build-cursors.py` is unchanged (sha256 stamp), so it is cheap at login.

Select with `XCURSOR_THEME=UltimitCursor-Mine XCURSOR_SIZE=24`.
