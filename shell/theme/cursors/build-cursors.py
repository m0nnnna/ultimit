#!/usr/bin/env python3
"""Build the Ultimit "Shard" Xcursor theme set (UltimitCursor-<Skin>).

Usage: build-cursors.py OUTDIR [--sheets DIR] [--skins Mine,Amber,...]

Draws every cursor with pycairo as vector paths at 24/32/48 px (no bitmap
downscaling), writes xcursorgen config files and runs /usr/bin/xcursorgen.
Original artwork: faceted crystal-shard language, dark-glass fill, thin accent
edge, one faint facet line, 1px near-black outer outline.
"""
import math
import os
import shutil
import subprocess
import sys
import tempfile

import cairo

SIZES = (24, 32, 48)
NOMINAL = 24
U = 52.0            # drawing canvas in design units
C = 26.0            # centre
OUTLINE = "#050607"

SKINS = {
    "Mine":    dict(accent="#d4ebff", fill="#14181d"),
    "Amber":   dict(accent="#ffb04a", fill="#1c1108"),
    "Silver":  dict(accent="#2c5b88", fill="#f6f7f9"),   # light skin
    "Verdant": dict(accent="#b9ff8c", fill="#0a1d0d"),   # accent from shell/Theme.qml
}


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
ARROW = [(4, 3), (4, 41), (14, 31), (22, 47), (28, 44), (20, 28), (34, 28)]
ARROW_SHADE = [(4, 3), (19, 28.5), (14, 31), (4, 41)]
ARROW_HS = (4, 3)
BC = (40.0, 38.5)    # badge centre


def arrow_shapes():
    return [P(ARROW, shade=ARROW_SHADE, facets=[[(4, 3), (19, 28.5)]])]


def badge_hex(r=7.6):
    return P(hexpts(BC[0], BC[1], r), shade=None)


def with_arrow(badge):
    return arrow_shapes() + badge


def at(pts, c=BC):
    return [(c[0] + x, c[1] + y) for x, y in pts]


def ring_cells(cx, cy, ro, ri, intens, rot0=-90, shrink=0.88):
    shapes = []
    for i in range(6):
        a0, a1 = rot0 + 60 * i, rot0 + 60 * (i + 1)
        pts = [(cx + ro * math.cos(math.radians(a0)), cy + ro * math.sin(math.radians(a0))),
               (cx + ro * math.cos(math.radians(a1)), cy + ro * math.sin(math.radians(a1))),
               (cx + ri * math.cos(math.radians(a1)), cy + ri * math.sin(math.radians(a1))),
               (cx + ri * math.cos(math.radians(a0)), cy + ri * math.sin(math.radians(a0)))]
        mx = sum(p[0] for p in pts) / 4
        my = sum(p[1] for p in pts) / 4
        pts = [(mx + (x - mx) * shrink, my + (y - my) * shrink) for x, y in pts]
        t = intens[i]
        shapes.append(P(pts, fill=("mix", 0.9 * t), ea=0.45 + 0.55 * t))
    return shapes


def intensities(frame, n=12):
    head = frame * 6.0 / n
    out = []
    for i in range(6):
        d = (head - i) % 6
        out.append(max(0.0, 1.0 - d / 3.4) ** 1.3)
    return out


def hand_pointer():
    pts = [(14, 2), (18, 6), (18, 19), (22, 17.5), (26, 19.5), (30, 22), (33, 25.5),
           (33, 35), (28, 43), (28, 47), (15, 47), (15, 42), (8, 33), (5, 27),
           (8, 25), (10, 28), (10, 6)]
    fy = lambda p: (p[0], 3.5 + (p[1] - 2) * (42.5 / 45.0))
    pts = [fy(p) for p in pts]
    return [P(pts, shade=[fy(p) for p in [(10, 6), (14, 2), (14, 28), (10, 28)]],
              facets=[[fy(p) for p in f] for f in ([(14, 2), (14, 26)], [(18, 19), (15, 30)])])]


def hand_open():
    pts = [(14, 17), (15.2, 15), (17.8, 15), (19, 17), (19, 22), (20.2, 22), (20.2, 11),
           (21.4, 9), (24, 9), (25.2, 11), (25.2, 20), (26.4, 20), (26.4, 9), (27.6, 7),
           (30.2, 7), (31.4, 9), (31.4, 20), (32.6, 20), (32.6, 13), (33.8, 11),
           (36.4, 11), (37.6, 13), (37.6, 29), (36, 40), (31, 47), (19, 47), (13, 41),
           (6, 31), (5, 27), (8, 25.5), (13, 30), (14, 30)]
    return [P(pts, shade=[(14, 15), (22.5, 15), (22.5, 47), (14, 47)],
              facets=[[(22.7, 9), (22.7, 24)], [(13, 30), (19, 38)]])]


def hand_closed():
    pts = [(13, 25), (14.5, 20.5), (19, 20.5), (20.5, 22.5), (21.5, 19), (26, 18), (30, 18),
           (31.5, 20), (33, 19), (37, 19.5), (39, 23), (39, 32), (35, 41), (32, 47),
           (18, 47), (15, 41), (10, 34), (10, 30)]
    return [P(pts, shade=[(10, 18), (25, 18), (25, 47), (10, 47)],
              facets=[[(25, 18), (25, 30)], [(13, 25), (20, 33)]])]


def ibeam(angle=0):
    pts = [(18, 5), (34, 5), (34, 9), (28.3, 11.5), (28.3, 40.5), (34, 43), (34, 47),
           (18, 47), (18, 43), (23.7, 40.5), (23.7, 11.5), (18, 9)]
    sh = [(18, 5), (26, 5), (26, 47), (18, 47)]
    fc = [[(26, 11.5), (26, 40.5)]]
    if angle:
        pts, sh = rot(pts, angle), rot(sh, angle)
        fc = [rot(f, angle) for f in fc]
    return [P(pts, shade=sh, facets=fc)]


def crosshair():
    arm = [(-1.7, -21), (1.7, -21), (1.3, -9), (0, -6.2), (-1.3, -9)]
    sh = []
    for k in range(4):
        sh.append(P(rel(rot(arm, 90 * k, (0, 0))), shade=None))
    dia = rel([(0, -2.6), (2.6, 0), (0, 2.6), (-2.6, 0)])
    sh.append(P(dia, fill="accent"))
    return sh


def fleur(tip=21, hb=14, hw=6.5, sw=2.0, diamond=False):
    arm = [(-sw, -hb), (-hw, -hb), (0, -tip), (hw, -hb), (sw, -hb), (sw, -sw)]
    pts = []
    for k in range(4):
        pts += rot(arm, 90 * k, (0, 0))
    pts = rel(pts)
    sh = [P(pts, shade=[(C - tip, C - tip), (C, C - tip), (C, C + tip), (C - tip, C + tip)],
            facets=[[(C, C - tip), (C, C - sw)], [(C - tip, C), (C - sw, C)]])]
    if diamond:
        sh.append(P(rel([(0, -2.8), (2.8, 0), (0, 2.8), (-2.8, 0)]), fill="accent"))
    return sh


def resize_single(angle):
    arrow = [(-19, -2.5), (3, -2.5), (3, -7), (13, 0), (3, 7), (3, 2.5), (-19, 2.5)]
    bar = [(15.5, -8), (18.5, -9.5), (18.5, 9.5), (15.5, 8)]
    f = lambda pts: rel(rot(pts, angle, (0, 0)))
    return [P(f(arrow), shade=f([(-19, -2.5), (13, 0), (-19, 0)]) if False else None,
              facets=[f([(-19, 0), (11, 0)])]),
            P(f(bar))]


def resize_double(angle):
    pts = [(-20, 0), (-11, -7.5), (-11, -2.5), (11, -2.5), (11, -7.5), (20, 0),
           (11, 7.5), (11, 2.5), (-11, 2.5), (-11, 7.5)]
    f = lambda p: rel(rot(p, angle, (0, 0)))
    return [P(f(pts), shade=f([(-20, 0), (20, 0), (11, 2.5), (-11, 2.5), (-11, 7.5)]),
              facets=[f([(-20, 0), (20, 0)])])]


def resize_split(vertical):
    a = 90 if vertical else 0
    f = lambda p: rel(rot(p, a, (0, 0)))
    left = [(-20, 0), (-12, -6.5), (-12, -2.5), (-2, -2.5), (-2, 2.5), (-12, 2.5), (-12, 6.5)]
    right = [(-x, y) for x, y in left]
    bar = [(-2.2, -11), (0, -14), (2.2, -11), (2.2, 11), (0, 14), (-2.2, 11)]
    return [P(f(bar), facets=[f([(0, -14), (0, 14)])]),
            P(f(left), facets=[f([(-20, 0), (-6, 0)])]),
            P(f(right), facets=[f([(20, 0), (6, 0)])])]


def forbidden(cx=C, cy=C, ro=19.5, ri=11.5):
    outer = hexpts(cx, cy, ro, -135)
    inner = hexpts(cx, cy, ri, -135)
    d = (math.cos(math.radians(45)), math.sin(math.radians(45)))
    n = (-d[1], d[0])
    hl, hw = ri + 3.0, 2.6
    bar = [(cx + d[0] * s + n[0] * w, cy + d[1] * s + n[1] * w)
           for s, w in ((-hl, -hw), (hl, -hw), (hl, hw), (-hl, hw))]
    return [P(outer, inner, rule="evenodd", facets=[hexpts(cx, cy, (ro + ri) / 2, -135) + [hexpts(cx, cy, (ro + ri) / 2, -135)[0]]] if False else ()),
            P(bar, edge=False, outline=False),
            L([bar[0], bar[3]], w=1.0, alpha=0.9), L([bar[1], bar[2]], w=1.0, alpha=0.9)]


def zoom(plus):
    lc = (21.0, 21.0)
    d = (math.sqrt(.5), math.sqrt(.5))
    n = (-d[1], d[0])
    w = 2.9
    pt = lambda s, ww: (lc[0] + d[0] * s + n[0] * ww, lc[1] + d[1] * s + n[1] * ww)
    handle = [pt(12, -w), pt(30, -w), pt(33, 0), pt(30, w), pt(12, w)]
    ring = P(hexpts(lc[0], lc[1], 14, -90), hexpts(lc[0], lc[1], 8.2, -90), rule="evenodd")
    sh = [P(handle, facets=[[pt(13, 0), pt(32, 0)]]), ring,
          L([(lc[0] - 4, lc[1]), (lc[0] + 4, lc[1])], w=1.9)]
    if plus:
        sh.append(L([(lc[0], lc[1] - 4), (lc[0], lc[1] + 4)], w=1.9))
    return sh


def pencil():
    T = (4.5, 47.5)
    d = (math.sqrt(.5), -math.sqrt(.5))
    n = (math.sqrt(.5), math.sqrt(.5))
    p = lambda a, b: (T[0] + d[0] * a + n[0] * b, T[1] + d[1] * a + n[1] * b)
    body = [p(0, 0), p(9, -3.8), p(39, -3.8), p(42, 0), p(39, 3.8), p(9, 3.8)]
    return [P(body, shade=[p(0, 0), p(42, 0), p(39, 3.8), p(9, 3.8)],
              facets=[[p(9, 0), p(41, 0)]]),
            L([p(9, -3.8), p(9, 3.8)], w=1.1, alpha=0.9),
            L([p(34, -3.8), p(34, 3.8)], w=1.1, alpha=0.6),
            P([p(0, 0), p(6, -2.4), p(6, 2.4)], fill="accent", edge=False, outline=False)]


def wait_frames(n=12):
    return [ring_cells(C, C, 19, 10.5, intensities(f, n)) for f in range(n)]


def progress_frames(n=12):
    out = []
    for f in range(n):
        out.append(arrow_shapes() + ring_cells(39.5, 38.5, 8.6, 4.4, intensities(f, n), shrink=0.86))
    return out


def plus_big():
    t, w = 21, 3.6
    pts = [(-w, -t), (w, -t), (w, -w), (t, -w), (t, w), (w, w), (w, t), (-w, t),
           (-w, w), (-t, w), (-t, -w), (-w, -w)]
    return [P(rel(pts), shade=[(C - t, C - t), (C, C - t), (C, C + t), (C - t, C + t)],
              facets=[[(C - t, C), (C + t, C)]])]


def badge_cursor(kind):
    s = arrow_shapes()
    if kind == "copy":
        s += [badge_hex(), L(at([(-3.6, 0), (3.6, 0)]), w=2.2), L(at([(0, -3.6), (0, 3.6)]), w=2.2)]
    elif kind == "alias":
        s += [badge_hex(), L(at([(-3.8, 0), (3.2, 0)]), w=2.0),
              L(at([(0.4, -3.3), (3.8, 0), (0.4, 3.3)]), w=2.0)]
    elif kind == "help":
        s += [badge_hex(8.0),
              L(at([(-2.6, -2.2), (-2.6, -3.4), (0, -4.4), (2.6, -3.4), (2.6, -1.4), (0, 0.4), (0, 1.4)]), w=1.5),
              L(at([(0, 3.1), (0, 4.0)]), w=1.7)]
    elif kind == "menu":
        s += [P(at([(-6.4, -6), (3.6, -6), (6.4, -3.2), (6.4, 6), (-6.4, 6)])),
              L(at([(-3.6, -2.8), (3.8, -2.8)]), w=1.3), L(at([(-3.6, 0.2), (3.8, 0.2)]), w=1.3),
              L(at([(-3.6, 3.2), (3.8, 3.2)]), w=1.3)]
    elif kind == "nodrop":
        s += [badge_hex(), L(at([(-3.6, -3.6), (3.6, 3.6)]), w=2.2)]
    elif kind == "dndmove":
        s += [P(at([(0, -7.4), (6.2, 0), (0, 7.4), (-6.2, 0)])),
              P(at([(0, -3.2), (2.6, 0), (0, 3.2), (-2.6, 0)]), fill="accent", edge=False, outline=False)]
    return s


# ---------------------------------------------------------------- registry
# name -> dict(frames=[shapes,...], hs=(ux,uy), delay=ms)
def build_registry():
    R = {}

    def add(name, shapes, hs, aliases=(), anim=None):
        frames = shapes if anim else [shapes]
        R[name] = dict(frames=frames, hs=hs, delay=60 if anim else 0, aliases=list(aliases))

    ctr = (C, C)
    add("default", arrow_shapes(), ARROW_HS, ["left_ptr", "arrow", "top_left_arrow", "right_ptr", "center_ptr"])
    add("text", ibeam(), ctr, ["xterm", "ibeam"])
    add("vertical-text", ibeam(90), ctr, ["vertical_text"])
    add("pointer", hand_pointer(), (14, 3.5),
        ["hand1", "hand2", "pointing_hand", "hand",
         "9d800788f1b08800ae810202380a0822", "e29285e634086352946a0e7090d73106"])
    add("wait", wait_frames(), ctr, ["watch"], anim=True)
    add("progress", progress_frames(), ARROW_HS,
        ["left_ptr_watch", "half-busy", "08e8e1c95fe2fc01f976f1e063a24ccd",
         "3ecb610c1bf2410f44200f48c40d3599"], anim=True)
    add("crosshair", crosshair(), ctr, ["cross", "tcross"])
    add("move", fleur(), ctr, ["fleur", "size_all", "4498f0e0c1937ffe01fd06f973665830",
                               "9081237383d90e509aa00f00170e968f"])
    add("all-scroll", fleur(tip=18, hb=12, hw=5.5, diamond=True), ctr, ["all_scroll"])
    add("grab", hand_open(), (26, 27), ["openhand", "9141b49c8149039304290b508d208c40"])
    add("grabbing", hand_closed(), (26, 28), ["closedhand", "08ffe1cb5fe6fc01f906f1c063814ccf"])
    add("not-allowed", forbidden(), ctr,
        ["crossed_circle", "forbidden", "circle", "03b6e0fcb3499374a867c041f52298f0"])
    add("no-drop", badge_cursor("nodrop"), ARROW_HS, ["dnd-none", "dnd_none", "dnd_no_drop"])
    add("help", badge_cursor("help"), ARROW_HS,
        ["question_arrow", "left_ptr_help", "whats_this", "d9ce0ab605698f320427677b458ad60b"])
    add("context-menu", badge_cursor("menu"), ARROW_HS, ["context_menu"])
    add("copy", badge_cursor("copy"), ARROW_HS,
        ["dnd-copy", "dnd_copy", "1081e37283d90000800003c07f3ef6bf",
         "6407b0e94181790501fd1e167b474872", "b66166c04f8c3109214a4fbd64a50fc8"])
    add("alias", badge_cursor("alias"), ARROW_HS,
        ["dnd-link", "dnd_link", "link", "3085a0e285430894940527032f8b26df",
         "640fb0e74195791501fd1ed57b41487f", "a2a266d0498c3104214a47bd64ab0fc8"])
    add("dnd-move", badge_cursor("dndmove"), ARROW_HS, [])
    add("cell", plus_big(), ctr, ["plus"])
    add("zoom-in", zoom(True), (21, 21), ["zoom_in"])
    add("zoom-out", zoom(False), (21, 21), ["zoom_out"])
    add("pencil", pencil(), (4.5, 47.5), ["draft", "draft_large", "draft_small"])
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
        self.outline = rgb(OUTLINE)
        self.shade = mix(self.fill, self.accent, 0.14)

    def colour(self, key):
        if isinstance(key, tuple):
            return mix(self.fill, self.accent, key[1])
        return {"fill": self.fill, "accent": self.accent, "shade": self.shade}[key]


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
    out_w = 1.0 * s * px
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
            c.set_line_width(edge_w + 2 * out_w)
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
                c.set_source_rgb(*skin.shade)
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
                c.set_line_width(edge_w)
                c.stroke()
        else:
            c.move_to(*sh["pts"][0])
            for p in sh["pts"][1:]:
                c.line_to(*p)
            if sh["close"]:
                c.close_path()
            c.set_source_rgba(*skin.colour(sh["color"]), sh["alpha"])
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


# ---------------------------------------------------------------- build
def build_theme(skin_name, outdir, registry, keep=None, warn=None):
    skin = Skin(skin_name)
    tname = "UltimitCursor-" + skin_name
    tdir = os.path.join(outdir, tname)
    if os.path.isdir(tdir):
        shutil.rmtree(tdir)
    os.makedirs(os.path.join(tdir, "cursors"))
    work = tempfile.mkdtemp(prefix="ulcur-")
    rendered = {}
    try:
        for name, cur in registry.items():
            cfg = []
            for fi, shapes in enumerate(cur["frames"]):
                for size in SIZES:
                    surf, (hx, hy) = render(skin, shapes, cur["hs"], size)
                    if warn is not None and fi == 0 and is_clipped(skin, shapes, cur["hs"], size):
                        warn.append("%s/%s frame %d @%d touches the canvas edge" % (tname, name, fi, size))
                    fn = os.path.join(work, "%s_%d_%d.png" % (name, size, fi))
                    surf.write_to_png(fn)
                    rendered[(name, size, fi)] = (surf, (hx, hy))
                    cfg.append("%d %d %d %s %d" % (size, hx, hy, fn, cur["delay"]))
            cfgfile = os.path.join(work, name + ".cfg")
            with open(cfgfile, "w") as f:
                f.write("\n".join(cfg) + "\n")
            subprocess.run(["xcursorgen", cfgfile, os.path.join(tdir, "cursors", name)],
                           check=True, cwd=work)
        for name, cur in registry.items():
            for a in cur["aliases"]:
                dst = os.path.join(tdir, "cursors", a)
                if os.path.lexists(dst):
                    os.unlink(dst)
                os.symlink(name, dst)
        with open(os.path.join(tdir, "index.theme"), "w") as f:
            f.write("[Icon Theme]\nName=%s\nComment=Ultimit Shard cursors (%s skin): "
                    "faceted dark-glass crystal shards with an accent edge\n"
                    "Inherits=Adwaita\n" % (tname, skin_name))
    finally:
        shutil.rmtree(work, ignore_errors=True)
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
    skins = list(SKINS)
    if "--sheets" in argv:
        sheets = argv[argv.index("--sheets") + 1]
        os.makedirs(sheets, exist_ok=True)
    if "--skins" in argv:
        skins = argv[argv.index("--skins") + 1].split(",")
    if not shutil.which("xcursorgen"):
        print("xcursorgen not found", file=sys.stderr)
        return 1
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
