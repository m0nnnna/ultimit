#!/usr/bin/env python3
"""Build the Ultimit Xcursor theme set (Izy or Shard style) (UltimitCursor-<Skin>).

Usage: build-cursors.py OUTDIR [--sheets DIR] [--skins Mine,Amber,...] [--theme Theme.qml]
                          [--style izy|shard]

Draws every cursor with pycairo as vector paths at 24/32/36/48/64 px (no bitmap
downscaling) and writes the Xcursor files itself (no xcursorgen needed).
The skins and their accent colours are read from shell/Theme.qml, so the
cursor follows Settings > Appearance; a new skin gets a cursor of its own.
Original artwork in the desktop's language: two-tone crystal shards (lit face
in the skin's accent, shadow face sunk toward its panel colour), hairlines,
chamfered chips and corner brackets, with one thin contrast outline.

The default style, "izy" ("cursorStyle" in shell.json, or --style), draws a
white two-tone dart with an accent rim and an accent wedge, plain badges (no
chips) and round busy rings. The other cursors (text, resize, move, ...) keep
the Shard shapes, drawn white with an accent rim. "shard" is the original set.
"""
import json
import math
import os
import re
import shutil
import struct
import sys

import cairo

SIZES = (24, 32, 36, 48, 64)
NOMINAL = 24
U = 52.0            # drawing canvas in design units
C = 26.0            # centre
OUTLINE = "#050607"
STYLES = ("izy", "shard")
STYLE = "izy"
LIGHT = "#f4f6f9"   # izy: lit face of the white shapes
MID = "#b3bac4"     # izy: their shadow face

THEME_QML = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Theme.qml")

# Glass fill per skin, tuned by eye against each skin's panels. A skin missing
# here gets its panel colour (shell/Theme.qml) as the fill.
FILLS = {
    "Mine":    "#14181d",
    "Amber":   "#1c1108",
    "Silver":  "#f6f7f9",   # light skin
    "Verdant": "#0a1d0d",
    "Sakura":  "#1f0a15",
    "Paper":   "#fbf8f1",   # light skin
    "Void":    "#05070b",
}
# Used only when Theme.qml cannot be read.
SKINS = {
    "Mine":    dict(accent="#d4ebff", fill="#14181d"),
    "Amber":   dict(accent="#ffb04a", fill="#1c1108"),
    "Silver":  dict(accent="#2c5b88", fill="#f6f7f9"),
    "Verdant": dict(accent="#b9ff8c", fill="#0a1d0d"),
    "Sakura":  dict(accent="#ff5fa2", fill="#1f0a15"),
    "Paper":   dict(accent="#0e7c70", fill="#fbf8f1"),
    "Void":    dict(accent="#4f9dff", fill="#05070b"),
}


def load_skins(path):
    """Skin name -> accent/fill, from the `skins` table in shell/Theme.qml."""
    try:
        src = open(path, encoding="utf-8").read()
    except OSError:
        return dict(SKINS)
    out = {}
    for m in re.finditer(r'^\s*(\w+)\s*:\s*\{(.*?)\}', src, re.M | re.S):
        body = m.group(2)
        acc = re.search(r'\baccent\s*:\s*"(#[0-9a-fA-F]{6})"', body)
        if not acc:
            continue
        name = m.group(1).capitalize()
        fill = FILLS.get(name)
        if fill is None:
            pan = re.search(r'\bpanel\s*:\s*\[\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)', body)
            fill = "#%02x%02x%02x" % tuple(int(v) for v in pan.groups()) if pan else "#14181d"
        out[name] = dict(accent=acc.group(1).lower(), fill=fill)
    return out or dict(SKINS)


def user_accent():
    """Your own accent ("accent" in shell.json, Settings > Appearance), lit on every skin."""
    p = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "ultimit", "shell.json")
    try:
        a = json.load(open(p)).get("accent", "")
    except Exception:
        return None
    return a.lower() if isinstance(a, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", a) else None


def user_style():
    """Cursor style ("cursorStyle" in shell.json); Izy when unset or unknown."""
    p = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "ultimit", "shell.json")
    try:
        v = json.load(open(p)).get("cursorStyle", "")
    except Exception:
        return "izy"
    return v if v in STYLES else "izy"


# ---------------------------------------------------------------- helpers
def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def rot(pts, deg, c=(C, C)):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(c[0] + (x - c[0]) * ca - (y - c[1]) * sa,
             c[1] + (x - c[0]) * sa + (y - c[1]) * ca) for x, y in pts]


def rel(pts, c=(C, C)):
    return [(c[0] + x, c[1] + y) for x, y in pts]


def hexpts(cx, cy, r, start=-90):
    return [(cx + r * math.cos(math.radians(start + 60 * i)),
             cy + r * math.sin(math.radians(start + 60 * i))) for i in range(6)]


def P(*sub, **kw):
    d = dict(kind="poly", fill="fill", edge=True, rule="nonzero", shade=None,
             facets=(), outline=True, ea=1.0)
    d.update(kw)
    d["sub"] = [list(s) for s in sub]
    return d


def L(pts, w=1.8, color="accent", alpha=1.0, close=False, cap="butt", outline=False):
    return dict(kind="line", pts=list(pts), w=w, color=color, alpha=alpha,
                close=close, cap=cap, outline=outline)


# ---------------------------------------------------------------- geometry
# The Ultimit look: lit crystal shards (the wallpaper), hairlines, chamfered
# chips and corner brackets. Solid shapes are two-tone shards (a lit face in the
# accent, a shadow face mixed toward the skin's panel); everything else is a
# thin accent line. One thin outline in the skin's contrast colour keeps it
# readable on any background.
ARROW = [(5, 3), (5, 44), (15.5, 34), (32, 33)]
ARROW_HS = (5, 3)
BC = (38.0, 38.0)    # badge centre
LW = 3.0             # line weight (design units; ~1.4 px at 24 px)


def shard(pts, lit):
    """Two-tone shard: silhouette `pts`, `lit` is the lit face (rest is shadow).
    Izy: white faces with an accent rim."""
    if STYLE == "izy":
        return P(pts, fill="mid", shade=lit, edge=True, lit=True, litc="light")
    return P(pts, fill="shade", shade=lit, edge=False, lit=True)


# Izy dart: tip, left wing, notch, right wing. The accent wedge sits in the
# notch, across the dart's axis, so it is a few pixels wide even at 24 px.
DART = [(7, 6), (11.5, 46), (19.5, 33.5), (35, 29)]


def arrow_shapes():
    if STYLE == "izy":
        t, lw, n, rw = DART
        ax = lambda f: (t[0] + (n[0] - t[0]) * f, t[1] + (n[1] - t[1]) * f)
        on = lambda a, b, f: (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
        wedge = [on(n, t, 0.06), on(n, lw, 0.30), ax(0.62), on(n, rw, 0.16)]
        return [P(DART, fill="light", shade=[t, rw, on(n, rw, 0.5)], edge=True, lit=True, litc="mid", ew=1.15),
                P(wedge, fill="accent", edge=False, outline=False)]
    return [shard(ARROW, ARROW[:3])]


def at(pts, c=BC):
    return [(c[0] + x, c[1] + y) for x, y in pts]


def head(tip, back, half, notch=2.2):
    """Arrowhead shard pointing +x: tip at x=tip, wings at x=tip-back."""
    pts = [(tip, 0), (tip - back, -half), (tip - back + notch, 0), (tip - back, half)]
    return pts, [(tip, 0), (tip - back, -half), (tip - back + notch, 0)]


def turned(shape_pts, angle, c=(C, C)):
    return [(c[0] + x * math.cos(math.radians(angle)) - y * math.sin(math.radians(angle)),
             c[1] + x * math.sin(math.radians(angle)) + y * math.cos(math.radians(angle)))
            for x, y in shape_pts]


def arrowhead(angle, tip, back=8.5, half=6.5, c=(C, C)):
    pts, lit = head(tip, back, half)
    return shard(turned(pts, angle, c), turned(lit, angle, c))


def chip(c=BC, r=8.5, k=3.0):
    """Ultimit's chamfered chip (corners cut top-left and bottom-right)."""
    return P(at([(-r + k, -r), (r, -r), (r, r - k), (r - k, r), (-r, r), (-r, -r + k)], c),
             fill="fill", edge=True)


def hex_line(cx, cy, r, start=-90, w=LW, alpha=1.0):
    pts = hexpts(cx, cy, r, start)
    return L(pts + [pts[0]], w=w, alpha=alpha, outline=True)


def hex_segments(cx, cy, r, intens, w):
    out = []
    pts = hexpts(cx, cy, r, -90)
    for i in range(6):
        a, b = pts[i], pts[(i + 1) % 6]
        g = 0.14
        a2 = (a[0] + (b[0] - a[0]) * g, a[1] + (b[1] - a[1]) * g)
        b2 = (b[0] + (a[0] - b[0]) * g, b[1] + (a[1] - b[1]) * g)
        out.append(L([a2, b2], w=w, alpha=0.16 + 0.84 * intens[i], outline=True))
    return out


def intensities(frame, n=12):
    head_ = frame * 6.0 / n
    out = []
    for i in range(6):
        d = (head_ - i) % 6
        out.append(max(0.0, 1.0 - d / 2.6) ** 1.5)
    return out


POINTER_HS = (19, 13)


def pointer():
    # An upright crystal spike with a tap burst over its tip: pointing, without a
    # cartoon hand, and not mistaken for the tilted arrow.
    tx, ty = POINTER_HS
    spike = shard([(tx, ty), (tx + 10.5, ty + 29), (tx, ty + 22.5), (tx - 10.5, ty + 29)],
                  [(tx, ty), (tx, ty + 22.5), (tx - 10.5, ty + 29)])
    rays = [L([(tx + 4.5 * math.cos(math.radians(a)), ty + 4.5 * math.sin(math.radians(a))),
               (tx + 9 * math.cos(math.radians(a)), ty + 9 * math.sin(math.radians(a)))],
              w=LW, outline=True) for a in (-90, -150, -30)]
    return rays + [spike]


def brackets(r, arm):
    out = []
    for k in range(4):
        out.append(L(turned([(-r, -r + arm), (-r, -r), (-r + arm, -r)], 90 * k, (C, C)),
                     w=LW, outline=True))
    return out


def diamond(r, c=(C, C)):
    return shard([(c[0], c[1] - r), (c[0] + r, c[1]), (c[0], c[1] + r), (c[0] - r, c[1])],
                 [(c[0], c[1] - r), (c[0], c[1] + r), (c[0] - r, c[1])])


def ibeam(angle=0):
    f = lambda pts: turned(pts, angle)
    return [L(f([(0, -17), (0, 17)]), w=LW, outline=True),
            L(f([(-6, -19), (-2, -19), (0, -17), (2, -19), (6, -19)]), w=LW, outline=True),
            L(f([(-6, 19), (-2, 19), (0, 17), (2, 19), (6, 19)]), w=LW, outline=True)]


def crosshair():
    sh = [L(turned([(0, -21), (0, -6)], 90 * k), w=LW, outline=True) for k in range(4)]
    return sh + [diamond(2.6)]


def fleur(tip=22, diamond_=False):
    sh = [L([(C - tip + 6, C), (C + tip - 6, C)], w=LW, outline=True),
          L([(C, C - tip + 6), (C, C + tip - 6)], w=LW, outline=True)]
    sh += [arrowhead(90 * k, tip, back=8, half=6) for k in range(4)]
    if diamond_:
        sh.append(diamond(4))
    return sh


def resize_single(angle):
    return [L(turned([(-18, 0), (8, 0)], angle), w=LW, outline=True),
            arrowhead(angle, 15, back=9, half=7),
            L(turned([(19.5, -10), (19.5, 10)], angle), w=LW, outline=True)]


def resize_double(angle):
    return [L(turned([(-13, 0), (13, 0)], angle), w=LW, outline=True),
            arrowhead(angle, 21, back=9, half=7), arrowhead(angle + 180, 21, back=9, half=7)]


def resize_split(vertical):
    a = 90 if vertical else 0
    return [L(turned([(0, -15), (0, 15)], a), w=LW, outline=True),
            L(turned([(5, 0), (13, 0)], a), w=LW, outline=True),
            L(turned([(-5, 0), (-13, 0)], a), w=LW, outline=True),
            arrowhead(a, 21, back=9, half=7), arrowhead(a + 180, 21, back=9, half=7)]


def forbidden():
    d = 11.5
    return [hex_line(C, C, 18, -90), L([(C - d, C + d * 0.62), (C + d, C - d * 0.62)], w=LW, outline=True)]


def zoom(plus):
    lc = (21.0, 21.0)
    sh = [L([(30.5, 30.5), (44, 44)], w=4.4, outline=True), hex_line(lc[0], lc[1], 13, -90),
          L([(lc[0] - 5, lc[1]), (lc[0] + 5, lc[1])], w=LW, outline=True)]
    if plus:
        sh.append(L([(lc[0], lc[1] - 5), (lc[0], lc[1] + 5)], w=LW, outline=True))
    return sh


def pencil():
    T = (6, 46) if STYLE == "izy" else (5, 47)
    d = (math.sqrt(.5), -math.sqrt(.5))
    n = (math.sqrt(.5), math.sqrt(.5))
    p = lambda a, b: (T[0] + d[0] * a + n[0] * b, T[1] + d[1] * a + n[1] * b)
    body = [p(0, 0), p(9, -3.6), p(40, -3.6), p(42.5, 0), p(40, 3.6), p(9, 3.6)]
    return [shard(body, [p(0, 0), p(9, -3.6), p(40, -3.6), p(42.5, 0)]),
            L([p(9, -3.6), p(9, 3.6)], w=1.4, color="fill", alpha=0.9)]


def wait_frames(n=12):
    return [hex_segments(C, C, 18, intensities(f, n), 4.6) + [diamond(3.2)] for f in range(n)]


def progress_frames(n=12):
    return [arrow_shapes() + [chip()] + hex_segments(BC[0], BC[1], 5.4, intensities(f, n), 2.8)
            for f in range(n)]


def plus_big():
    return [L([(C - 16, C), (C + 16, C)], w=LW, outline=True),
            L([(C, C - 16), (C, C + 16)], w=LW, outline=True), diamond(3.4)]


def badge_cursor(kind):
    s = arrow_shapes() + [chip()]
    # glyphs drawn on a 7 x 7 grid, scaled up to the chip
    g = lambda pts, w=2.0: L(at([(x * 1.3, y * 1.3) for x, y in pts]), w=w * 1.35)
    if kind == "copy":
        s += [g([(-3.6, 0), (3.6, 0)]), g([(0, -3.6), (0, 3.6)])]
    elif kind == "alias":
        s += [g([(-3.6, 3.4), (-3.6, -0.6), (3.4, -0.6)]), g([(0.6, -3.4), (3.4, -0.6), (0.6, 2.2)])]
    elif kind == "help":
        s += [g([(-2.6, -2.0), (-2.6, -3.6), (2.6, -3.6), (2.6, -1.0), (0, 0.6), (0, 1.6)], 1.6),
              g([(0, 3.0), (0, 4.4)], 1.8)]
    elif kind == "menu":
        s += [g([(-3.8, -2.8), (3.8, -2.8)], 1.5), g([(-3.8, 0), (3.8, 0)], 1.5),
              g([(-3.8, 2.8), (1.8, 2.8)], 1.5)]
    elif kind == "nodrop":
        s += [g([(-3.6, 3.6), (3.6, -3.6)])]
    elif kind == "dndmove":
        s += [P(at([(0, -4.6), (4.6, 0), (0, 4.6), (-4.6, 0)]), fill="accent", edge=False, outline=False)]
    return s


# ---------------------------------------------------------------- izy
def arc(cx, cy, r, a0, a1, n=10):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def stadium(c, length, r, angle):
    """Closed outline of a rounded link, centred on c, long axis at `angle`."""
    h = length / 2 - r
    pts = rel(arc(h, 0, r, -90, 90, 8) + arc(-h, 0, r, 90, 270, 8), (0, 0))
    return turned(pts + [pts[0]], angle, c)


def ring_segments(cx, cy, r, intens, w, n=8):
    """A dashed ring, one dash per value in intens (0..1 brightness)."""
    out = []
    for i in range(n):
        a = -90 + 360.0 * i / n
        span = 360.0 / n * 0.56
        out.append(L(arc(cx, cy, r, a - span / 2, a + span / 2, 4), w=w,
                     alpha=0.22 + 0.78 * intens[i], outline=True))
    return out


def ring_intensities(frame, frames=12, n=8):
    head_ = frame * float(n) / frames
    return [max(0.0, 1.0 - ((head_ - i) % n) / 3.2) ** 1.5 for i in range(n)]


def izy_badge(kind, c=BC):
    """Izy badges: a plain accent glyph next to the dart, no chip."""
    g = lambda pts, w=2.4: L(at(pts, c), w=w, outline=True)
    if kind == "link":
        return [L(stadium((c[0] - 2.6, c[1] + 2.6), 12, 3.3, -45), w=2.2, outline=True),
                L(stadium((c[0] + 2.6, c[1] - 2.6), 12, 3.3, -45), w=2.2, outline=True)]
    if kind == "copy":
        return [g([(-7, 0), (7, 0)], 2.8), g([(0, -7), (0, 7)], 2.8)]
    if kind == "alias":
        return [g([(-6, 6), (-6, -1), (5, -1)]), g([(1, -5.5), (5.5, -1), (1, 3.5)])]
    if kind == "help":
        return [g(arc(0, -3, 5, 180, 360, 8) + arc(0, -3, 5, 0, 70, 4) + [(0, 3.5)], 2.4),
                g([(0, 6.2), (0, 8.6)], 2.6)]
    if kind == "menu":
        return [g([(-7, -5), (7, -5)], 2.4), g([(-7, 0), (7, 0)], 2.4), g([(-7, 5), (3, 5)], 2.4)]
    if kind == "nodrop":
        return [L(arc(c[0], c[1], 7, 0, 360, 20), w=2.2, outline=True),
                g([(-4.9, 4.9), (4.9, -4.9)], 2.2)]
    if kind == "dndmove":
        k = 2.5
        return [g([(-7 + k, -7), (7, -7), (7, 7 - k), (7 - k, 7), (-7, 7), (-7, -7 + k), (-7 + k, -7)], 2.2)]
    return []


def izy_badge_cursor(kind):
    return arrow_shapes() + izy_badge(kind)


def izy_wait_frames(n=12):
    return [ring_segments(C, C, 16, ring_intensities(f, n), 4.4) + [diamond(3.2)] for f in range(n)]


def izy_progress_frames(n=12):
    return [arrow_shapes() + ring_segments(BC[0], BC[1], 7.5, ring_intensities(f, n), 3.0)
            for f in range(n)]


def izy_forbidden():
    d = 17 * math.sqrt(.5)
    return [L(arc(C, C, 17, 0, 360, 36), w=LW + 0.6, outline=True),
            L([(C - d, C + d), (C + d, C - d)], w=LW + 0.6, outline=True)]


# ---------------------------------------------------------------- registry
# name -> dict(frames=[shapes,...], hs=(ux,uy), delay=ms)
def build_registry():
    R = {}

    def add(name, shapes, hs, aliases=(), anim=None):
        frames = shapes if anim else [shapes]
        R[name] = dict(frames=frames, hs=hs, delay=60 if anim else 0, aliases=list(aliases))

    ctr = (C, C)
    izy = STYLE == "izy"
    arrow_hs = DART[0] if izy else ARROW_HS
    badge = izy_badge_cursor if izy else badge_cursor
    add("default", arrow_shapes(), arrow_hs, ["left_ptr", "arrow", "top_left_arrow", "right_ptr", "center_ptr"])
    add("text", ibeam(), ctr, ["xterm", "ibeam"])
    add("vertical-text", ibeam(90), ctr, ["vertical_text"])
    add("pointer", izy_badge_cursor("link") if izy else pointer(), arrow_hs if izy else POINTER_HS,
        ["hand1", "hand2", "pointing_hand", "hand",
         "9d800788f1b08800ae810202380a0822", "e29285e634086352946a0e7090d73106"])
    add("wait", izy_wait_frames() if izy else wait_frames(), ctr, ["watch"], anim=True)
    add("progress", izy_progress_frames() if izy else progress_frames(), arrow_hs,
        ["left_ptr_watch", "half-busy", "08e8e1c95fe2fc01f976f1e063a24ccd",
         "3ecb610c1bf2410f44200f48c40d3599"], anim=True)
    add("crosshair", crosshair(), ctr, ["cross", "tcross"])
    add("move", fleur(tip=20 if izy else 22), ctr, ["fleur", "size_all", "4498f0e0c1937ffe01fd06f973665830",
                               "9081237383d90e509aa00f00170e968f"])
    add("all-scroll", fleur(tip=19, diamond_=True), ctr, ["all_scroll"])
    add("grab", brackets(14, 7) + [diamond(2.4)], ctr, ["openhand", "9141b49c8149039304290b508d208c40"])
    add("grabbing", brackets(9, 5) + [diamond(4.2)], ctr, ["closedhand", "08ffe1cb5fe6fc01f906f1c063814ccf"])
    add("not-allowed", izy_forbidden() if izy else forbidden(), ctr,
        ["crossed_circle", "forbidden", "circle", "03b6e0fcb3499374a867c041f52298f0"])
    add("no-drop", badge("nodrop"), arrow_hs, ["dnd-none", "dnd_none", "dnd_no_drop"])
    add("help", badge("help"), arrow_hs,
        ["question_arrow", "left_ptr_help", "whats_this", "d9ce0ab605698f320427677b458ad60b"])
    add("context-menu", badge("menu"), arrow_hs, ["context_menu"])
    add("copy", badge("copy"), arrow_hs,
        ["dnd-copy", "dnd_copy", "1081e37283d90000800003c07f3ef6bf",
         "6407b0e94181790501fd1e167b474872", "b66166c04f8c3109214a4fbd64a50fc8"])
    add("alias", badge("alias"), arrow_hs,
        ["dnd-link", "dnd_link", "link", "3085a0e285430894940527032f8b26df",
         "640fb0e74195791501fd1ed57b41487f", "a2a266d0498c3104214a47bd64ab0fc8"])
    add("dnd-move", badge("dndmove"), arrow_hs, [])
    add("cell", plus_big(), ctr, ["plus"])
    add("zoom-in", zoom(True), (21, 21), ["zoom_in"])
    add("zoom-out", zoom(False), (21, 21), ["zoom_out"])
    add("pencil", pencil(), (6, 46) if izy else (5, 47), ["draft", "draft_large", "draft_small"])
    # resize family
    for name, ang in (("e-resize", 0), ("se-resize", 45), ("s-resize", 90), ("sw-resize", 135),
                      ("w-resize", 180), ("nw-resize", 225), ("n-resize", 270), ("ne-resize", 315)):
        al = {"e-resize": ["right_side"], "w-resize": ["left_side"], "n-resize": ["top_side"],
              "s-resize": ["bottom_side"], "nw-resize": ["top_left_corner"],
              "ne-resize": ["top_right_corner"], "sw-resize": ["bottom_left_corner"],
              "se-resize": ["bottom_right_corner"]}[name]
        add(name, resize_single(ang), ctr, al)
    add("ew-resize", resize_double(0), ctr,
        ["sb_h_double_arrow", "size_hor", "h_double_arrow", "028006030e0e7ebffc7f7070c0600140",
         "14fef782d02440884392942c11205230"])
    add("ns-resize", resize_double(90), ctr,
        ["sb_v_double_arrow", "size_ver", "v_double_arrow", "00008160000006810000408080010102",
         "2870a09082c103050810ffdffffe0204"])
    add("nesw-resize", resize_double(315), ctr,
        ["bd_double_arrow", "size_bdiag", "c7088f0f3e6c8088236ef8e1e3e70000"])
    add("nwse-resize", resize_double(45), ctr,
        ["fd_double_arrow", "size_fdiag", "fcf1c3c7cd4491d801f1e1c78f100000"])
    add("col-resize", resize_split(False), ctr, ["split_h"])
    add("row-resize", resize_split(True), ctr, ["split_v"])
    return R


# ---------------------------------------------------------------- rendering
class Skin:
    def __init__(self, name):
        s = SKINS[name]
        self.name = name
        self.accent = rgb(s["accent"])
        self.fill = rgb(s["fill"])
        light = sum(self.fill) / 3 > 0.5
        # Contrast outline: near-black on dark skins, white on light ones. The
        # izy shapes are white, so they always get the dark one.
        self.outline = (1.0, 1.0, 1.0) if light and STYLE != "izy" else rgb(OUTLINE)
        self.light, self.mid = rgb(LIGHT), rgb(MID)
        # Izy hairlines: the accent, or white when the accent is too dark to
        # read on a dark window (Silver); the rims keep the accent.
        lum = 0.2126 * self.accent[0] + 0.7152 * self.accent[1] + 0.0722 * self.accent[2]
        self.line = self.light if STYLE == "izy" and lum < 0.4 else self.accent
        # Shadow face of a shard: the accent sunk toward the panel colour.
        self.shade = mix(self.accent, self.fill, 0.42)

    def colour(self, key):
        if isinstance(key, tuple):
            return mix(self.fill, self.accent, key[1])
        return {"fill": self.fill, "accent": self.accent, "shade": self.shade,
                "light": self.light, "mid": self.mid}[key]


def trace(c, shape):
    for sub in shape["sub"]:
        c.move_to(*sub[0])
        for p in sub[1:]:
            c.line_to(*p)
        c.close_path()


def hotspot_px(hs, size):
    k = size / U
    return max(0, int(round(hs[0] * k))), max(0, int(round(hs[1] * k)))


def render(skin, shapes, hs, size, pad=0):
    k = size / U
    hx, hy = hotspot_px(hs, size)
    tx, ty = hx + 0.5 - hs[0] * k, hy + 0.5 - hs[1] * k
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, size + 2 * pad, size + 2 * pad)
    c = cairo.Context(surf)
    c.set_antialias(cairo.ANTIALIAS_BEST)
    c.translate(tx + pad, ty + pad)
    c.scale(k, k)
    px = 1.0 / k
    s = size / NOMINAL
    edge_w = (0.85 * s + 0.25) * px
    out_w = 1.2 * s * px
    c.set_miter_limit(3)

    # pass 1: dark outer outline
    for sh in shapes:
        if not sh["outline"]:
            continue
        c.set_source_rgb(*skin.outline)
        c.set_line_join(cairo.LINE_JOIN_ROUND)
        c.set_line_cap(cairo.LINE_CAP_ROUND)
        if sh["kind"] == "poly":
            trace(c, sh)
            c.set_fill_rule(cairo.FILL_RULE_EVEN_ODD if sh["rule"] == "evenodd" else cairo.FILL_RULE_WINDING)
            c.set_line_width((edge_w * sh.get("ew", 1.0) if sh["edge"] else 0) + 2 * out_w)
            c.stroke()
        else:
            c.move_to(*sh["pts"][0])
            for p in sh["pts"][1:]:
                c.line_to(*p)
            c.set_line_width(sh["w"] + 2 * out_w)
            c.stroke()

    # pass 2: glass, facets, accent edge
    for sh in shapes:
        if sh["kind"] == "poly":
            c.set_fill_rule(cairo.FILL_RULE_EVEN_ODD if sh["rule"] == "evenodd" else cairo.FILL_RULE_WINDING)
            if sh["fill"] != "none":
                trace(c, sh)
                c.set_source_rgb(*skin.colour(sh["fill"]))
                c.fill_preserve()
                c.new_path()
            if sh["shade"]:
                c.save()
                trace(c, sh)
                c.clip()
                c.move_to(*sh["shade"][0])
                for p in sh["shade"][1:]:
                    c.line_to(*p)
                c.close_path()
                c.set_source_rgb(*(skin.colour(sh.get("litc", "accent")) if sh.get("lit") else skin.shade))
                c.fill()
                c.restore()
            if sh["facets"]:
                c.save()
                trace(c, sh)
                c.clip()
                c.set_line_cap(cairo.LINE_CAP_BUTT)
                c.set_line_join(cairo.LINE_JOIN_MITER)
                c.set_line_width(0.8 * s * px)
                c.set_source_rgba(*skin.accent, 0.6)
                for f in sh["facets"]:
                    c.move_to(*f[0])
                    for p in f[1:]:
                        c.line_to(*p)
                    c.stroke()
                c.restore()
            if sh["edge"]:
                trace(c, sh)
                c.set_source_rgba(*skin.accent, sh["ea"])
                c.set_line_join(cairo.LINE_JOIN_MITER)
                c.set_line_width(edge_w * sh.get("ew", 1.0))
                c.stroke()
        else:
            c.move_to(*sh["pts"][0])
            for p in sh["pts"][1:]:
                c.line_to(*p)
            if sh["close"]:
                c.close_path()
            col = skin.line if sh["color"] == "accent" else skin.colour(sh["color"])
            c.set_source_rgba(*col, sh["alpha"])
            c.set_line_cap(cairo.LINE_CAP_SQUARE if sh["cap"] == "square" else cairo.LINE_CAP_BUTT)
            c.set_line_join(cairo.LINE_JOIN_MITER)
            c.set_line_width(max(sh["w"], 0.95 * s * px))
            c.stroke()
    return surf, (hx, hy)


def is_clipped(skin, shapes, hs, size):
    """Render on a padded canvas; True if any visible ink falls outside size x size."""
    pad = 8
    surf, _ = render(skin, shapes, hs, size, pad)
    n = size + 2 * pad
    d, st = surf.get_data(), surf.get_stride()
    for y in range(n):
        for x in range(n):
            if (x < pad or y < pad or x >= pad + size or y >= pad + size) and d[y * st + x * 4 + 3] > 12:
                return True
    return False


# ---------------------------------------------------------------- Xcursor files
XCURSOR_IMAGE = 0xfffd0002


def write_xcursor(path, images):
    """images: [(nominal, surface, (hx, hy), delay_ms)]. cairo's ARGB32 is the
    premultiplied native-endian ARGB Xcursor stores (little-endian here)."""
    toc, chunks, pos = [], [], 16 + 12 * len(images)
    for nominal, surf, (hx, hy), delay in images:
        surf.flush()
        w, h, st = surf.get_width(), surf.get_height(), surf.get_stride()
        data = bytes(surf.get_data())
        px = b"".join(data[y * st:y * st + w * 4] for y in range(h))
        chunk = struct.pack("<9I", 36, XCURSOR_IMAGE, nominal, 1, w, h, hx, hy, delay) + px
        toc.append(struct.pack("<3I", XCURSOR_IMAGE, nominal, pos))
        chunks.append(chunk)
        pos += len(chunk)
    with open(path, "wb") as f:
        f.write(b"Xcur" + struct.pack("<3I", 16, 0x10000, len(images)))
        f.write(b"".join(toc))
        f.write(b"".join(chunks))


# ---------------------------------------------------------------- build
def build_theme(skin_name, outdir, registry, keep=None, warn=None):
    skin = Skin(skin_name)
    tname = "UltimitCursor-" + skin_name
    tdir = os.path.join(outdir, tname)
    if os.path.isdir(tdir):
        shutil.rmtree(tdir)
    os.makedirs(os.path.join(tdir, "cursors"))
    rendered = {}
    for name, cur in registry.items():
        images = []
        for size in SIZES:
            for fi, shapes in enumerate(cur["frames"]):
                surf, (hx, hy) = render(skin, shapes, cur["hs"], size)
                if warn is not None and fi == 0 and is_clipped(skin, shapes, cur["hs"], size):
                    warn.append("%s/%s frame %d @%d touches the canvas edge" % (tname, name, fi, size))
                if keep is not None:
                    rendered[(name, size, fi)] = (surf, (hx, hy))
                images.append((size, surf, (hx, hy), cur["delay"]))
        write_xcursor(os.path.join(tdir, "cursors", name), images)
    for name, cur in registry.items():
        for a in cur["aliases"]:
            dst = os.path.join(tdir, "cursors", a)
            if os.path.lexists(dst):
                os.unlink(dst)
            os.symlink(name, dst)
    with open(os.path.join(tdir, "index.theme"), "w") as f:
        desc = ("Ultimit Izy cursors (%s skin): white darts with an accent rim" if STYLE == "izy"
                else "Ultimit Shard cursors (%s skin): two-tone crystal shards and accent hairlines")
        f.write("[Icon Theme]\nName=%s\nComment=%s\nInherits=Adwaita\n" % (tname, desc % skin_name))
    if keep is not None:
        keep.update(rendered)
    return tdir


# ---------------------------------------------------------------- contact sheet
def contact_sheet(skin_name, registry, rendered, path):
    names = list(registry.keys())
    bgs = [("dark", "#0f1215"), ("white", "#ffffff"), ("grey", "#808890"), ("amber", None)]
    tile_w, row_h, label_w = 104, 64, 118
    cols = 3
    cell_w = label_w + tile_w * len(bgs)
    rows = math.ceil(len(names) / cols)
    anim_h = 2 * 72 + 20
    W, H = cell_w * cols, rows * row_h + anim_h + 10
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, W, H)
    c = cairo.Context(surf)
    c.set_source_rgb(0.12, 0.13, 0.15)
    c.paint()
    c.select_font_face("DejaVu Sans")
    c.set_font_size(10)

    def tile(x, y, w, h, bg):
        if bg[1] is None:
            g = cairo.LinearGradient(x, y, x + w, y + h)
            g.add_color_stop_rgb(0, *rgb("#b84d05"))
            g.add_color_stop_rgb(1, *rgb("#f8cf96"))
            c.set_source(g)
        else:
            c.set_source_rgb(*rgb(bg[1]))
        c.rectangle(x, y, w, h)
        c.fill()

    def put(name, size, frame, x, y):
        s, (hx, hy) = rendered[(name, size, frame)]
        c.set_source_surface(s, x, y)
        c.paint()
        c.set_source_rgb(1, 0, 0)
        c.rectangle(x + hx, y + hy, 1, 1)
        c.fill()

    for i, name in enumerate(names):
        col, row = i % cols, i // cols
        x0, y0 = col * cell_w, row * row_h
        c.set_source_rgb(0.85, 0.87, 0.9)
        c.move_to(x0 + 6, y0 + 36)
        c.show_text(name)
        for j, bg in enumerate(bgs):
            bx = x0 + label_w + j * tile_w
            tile(bx, y0 + 1, tile_w - 2, row_h - 2, bg)
            put(name, 24, 0, bx + 8, y0 + 4)
            put(name, 48, 0, bx + 44, y0 + 8)
    # animation strips
    y = rows * row_h + 6
    for an in ("wait", "progress"):
        if len(registry[an]["frames"]) < 2:
            continue
        for j, bg in enumerate(bgs[:2]):
            pass
        tile(0, y, W, 66, bgs[0])
        c.set_source_rgb(0.85, 0.87, 0.9)
        c.move_to(6, y + 12)
        c.show_text(an + " frames @48 / @24")
        for f in range(len(registry[an]["frames"])):
            put(an, 48, f, 130 + f * 60, y + 8)
            put(an, 24, f, 130 + f * 60 + 18, y + 8 + 52 - 24 if False else y + 8 + 50)
        y += 70
    surf.write_to_png(path)


def main(argv):
    if len(argv) < 2 or argv[1].startswith("-"):
        print(__doc__)
        return 2
    outdir = argv[1]
    sheets = None
    theme = argv[argv.index("--theme") + 1] if "--theme" in argv else THEME_QML
    global STYLE
    STYLE = argv[argv.index("--style") + 1] if "--style" in argv else user_style()
    if STYLE not in STYLES:
        print("unknown style %r (want %s)" % (STYLE, "|".join(STYLES)), file=sys.stderr)
        return 2
    found = load_skins(theme)
    acc = user_accent()
    for v in found.values():
        v["accent"] = acc or v["accent"]
    SKINS.clear()
    SKINS.update(found)
    skins = list(SKINS)
    if "--sheets" in argv:
        sheets = argv[argv.index("--sheets") + 1]
        os.makedirs(sheets, exist_ok=True)
    if "--skins" in argv:
        skins = argv[argv.index("--skins") + 1].split(",")
    os.makedirs(outdir, exist_ok=True)
    reg = build_registry()
    warns = []
    for sk in skins:
        keep = {} if sheets else None
        build_theme(sk, outdir, reg, keep, warns)
        if sheets:
            contact_sheet(sk, reg, keep, os.path.join(sheets, "contact-sheet-%s.png" % sk))
    for w in warns:
        print("warning:", w, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
