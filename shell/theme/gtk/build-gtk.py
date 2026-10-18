#!/usr/bin/env python3
"""Generate the Ultimit GTK themes (Mine, Amber, Silver, Verdant + alias).

Stdlib only. Reads templates/gtk-3.0.css.in and templates/gtk-4.0.css.in,
substitutes one palette per skin and writes complete theme directories:

    OUT/Ultimit-Mine/{index.theme,gtk-3.0/gtk.css,gtk-4.0/gtk.css}
    OUT/Ultimit-Amber/ ...  Ultimit-Silver/ ...  Ultimit-Verdant/ ...
    OUT/Ultimit -> alias of the current skin (--alias SKIN, default: read from
                   ~/.config/ultimit/shell.json, fallback mine)

Template syntax: {{ python-expression }} evaluated with the palette tokens as
variables plus helper functions (chamfer, svg_btn, mix, alpha, ...).
Palettes mirror shell/Theme.qml; keep them in sync.

With --flatpak the GTK4 themes import upstream libadwaita's stylesheet
(Flathub runtimes) instead of Ubuntu's Yaru-patched one.

Usage: build-gtk.py OUT_DIR [--alias SKIN] [--only SKIN] [--flatpak]
"""
import colorsys, json, os, re, sys

HERE = os.path.dirname(os.path.realpath(__file__))
TPL = os.path.join(HERE, "templates")

# Mirror of Theme.qml skins (panel/panel2/line are rgba there).
SKINS = {
    "mine": dict(
        panel=(13, 15, 18), fg=(238, 241, 244), dim=(141, 148, 158),
        line=(235, 240, 245, .16), line2=(235, 240, 245, .48),
        accent=(212, 235, 255), on_acc=(7, 9, 11),
        ok=(143, 227, 176), warn=(255, 217, 143), bad=(255, 138, 138), light=False),
    "amber": dict(
        panel=(34, 17, 5), fg=(255, 244, 230), dim=(220, 180, 140),
        line=(255, 226, 196, .20), line2=(255, 226, 196, .55),
        accent=(255, 176, 74), on_acc=(42, 20, 4),
        ok=(143, 227, 176), warn=(255, 217, 143), bad=(255, 138, 138), light=False),
    "silver": dict(
        panel=(248, 249, 251), fg=(20, 23, 27), dim=(90, 98, 109),
        line=(20, 24, 30, .16), line2=(20, 24, 30, .50),
        accent=(44, 91, 136), on_acc=(255, 255, 255),
        ok=(31, 138, 82), warn=(166, 107, 0), bad=(192, 57, 43), light=True),
    "verdant": dict(
        panel=(5, 20, 8), fg=(239, 251, 233), dim=(163, 204, 149),
        line=(220, 255, 205, .18), line2=(220, 255, 205, .50),
        accent=(185, 255, 140), on_acc=(8, 32, 8),
        ok=(143, 227, 176), warn=(255, 217, 143), bad=(255, 138, 138), light=False),
}
NAMES = {"mine": "Mine", "amber": "Amber", "silver": "Silver", "verdant": "Verdant"}


def hexc(c):
    return "#%02x%02x%02x" % tuple(int(round(v)) for v in c[:3])


def rgba(c, a=None):
    a = c[3] if a is None and len(c) > 3 else (1 if a is None else a)
    return "rgba(%d,%d,%d,%s)" % (c[0], c[1], c[2], ("%.3f" % a).rstrip("0").rstrip("."))


def mix(a, b, t):
    """a*(1-t) + b*t on rgb triples."""
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


def parse_css(c):
    """'#rrggbb' or 'rgba(r,g,b,a)' -> (r,g,b,a)."""
    if c.startswith("#"):
        return (int(c[1:3], 16), int(c[3:5], 16), int(c[5:7], 16), 1.0)
    m = re.match(r"rgba?\(([^)]*)\)", c)
    p = [float(x) for x in m.group(1).split(",")]
    return (p[0], p[1], p[2], p[3] if len(p) > 3 else 1.0)


def tr(c):
    p = parse_css(c)
    return "rgba(%d,%d,%d,0)" % p[:3]


def user_accent():
    """Your own accent ("accent": "#rrggbb" in shell.json), or None for the skin's own."""
    p = os.path.expanduser("~/.config/ultimit/shell.json")
    try:
        a = json.load(open(p)).get("accent", "")
    except Exception:
        return None
    return a.lower() if isinstance(a, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", a) else None


def accented(s, a):
    """Skin palette s with accent a ("#rrggbb"): the text on it turns dark or light by its
    brightness, "bad" moves to orange when the accent is red-ish. Mirrors Theme.qml."""
    if not a:
        return s
    c = tuple(int(a[i:i + 2], 16) for i in (1, 3, 5))
    lin = [v / 255 / 12.92 if v / 255 <= 0.04045 else ((v / 255 + 0.055) / 1.055) ** 2.4 for v in c]
    lum = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
    h, sat, _ = colorsys.rgb_to_hsv(*(v / 255 for v in c))
    reddish = sat >= 0.4 and (h <= 20 / 360 or h >= 330 / 360)
    s = dict(s, accent=c, on_acc=(8, 9, 11) if lum > 0.18 else (255, 255, 255))
    if reddish:
        s["bad"] = (179, 84, 0) if s["light"] else (255, 154, 82)
    return s


def palette(name):
    s = accented(SKINS[name], user_accent())
    light = s["light"]
    panel, fg, accent = s["panel"], s["fg"], s["accent"]
    black, white = (0, 0, 0), (255, 255, 255)
    if light:
        bg = mix(panel, black, .035)
        deep = white
        side = mix(panel, black, .06)
        field = white
        hover = mix(panel, black, .07)
        card = mix(panel, white, .5)
        thumb = mix(panel, black, .12)
    else:
        bg = mix(panel, black, .22)
        deep = mix(panel, black, .60)
        side = mix(panel, black, .35)
        field = mix(deep, fg, .06)
        hover = mix(bg, fg, .09)
        card = mix(bg, fg, .05)
        thumb = mix(bg, fg, .12)
    if name == "mine":  # exact historical values
        bg, deep, side = (10, 12, 15), (5, 6, 7), (8, 10, 12)
    sel = mix(bg, accent, .22 if not light else .20)
    selst = mix(bg, accent, .38 if not light else .32)   # text selection (solid)
    ns = dict(
        name=name, Name=NAMES[name], light=light,
        scheme="light" if light else "dark",
        dark_suffix="" if light else "-dark",
        panel=hexc(panel), bg=hexc(bg), deep=hexc(deep), side=hexc(side),
        field=hexc(field), hover=hexc(hover), card=hexc(card), thumb=hexc(thumb),
        sel=hexc(sel), selst=hexc(selst),
        fg=hexc(fg), dim=hexc(s["dim"]),
        line=rgba(s["line"]), line2=rgba(s["line2"]),
        line_solid=hexc(mix(bg, fg, .16)), line2_solid=hexc(mix(bg, fg, .48)),
        accent=hexc(accent), on_acc=hexc(s["on_acc"]),
        accent20=rgba(accent + (.20,)), accent40=rgba(accent + (.40,)),
        ok=hexc(s["ok"]), warn=hexc(s["warn"]), bad=hexc(s["bad"]),
        shadow=rgba((0, 0, 0, .35 if light else .5)),
        shade=rgba((0, 0, 0, .15 if light else .4)),
    )
    ns["accent_hover"] = hexc(mix(accent, white, .18) if not light else mix(accent, black, .15))
    return ns


# --- template helpers -------------------------------------------------------
def chamfer(line, cut, c=6):
    """Declarations drawing a 1px outline whose top-left and bottom-right
    corners are cut at 45 degrees. `line` is the outline colour, `cut` the
    colour of whatever lies behind the widget (paints the cut corners).
    The fill is the caller's background-color. CSS has no clip-path, so the
    four edges and both diagonals are background-image gradients."""
    t = c / (2 ** 0.5)           # gradient offset of the anti-diagonal
    z = tr(line)
    a, b, d, e = t - .9, t - .35, t + .35, t + .9
    tl = ("linear-gradient(135deg, %s 0, %s %.2fpx, %s %.2fpx, %s %.2fpx, %s %.2fpx)"
          % (cut, cut, a, line, b, line, d, z, e))
    br = tl.replace("135deg", "315deg")
    edge = lambda d_: "linear-gradient(to %s, %s, %s)" % (d_, line, line)
    imgs = [tl, br, edge("right"), edge("right"), edge("bottom"), edge("bottom")]
    sizes = ["%dpx %dpx" % (c, c)] * 2 + ["100% 1px"] * 2 + ["1px 100%"] * 2
    pos = ["left top", "right bottom", "left top", "left bottom", "left top", "right top"]
    return ("background-image: %s; background-size: %s; background-position: %s; "
            "background-repeat: no-repeat;" % (", ".join(imgs), ", ".join(sizes), ", ".join(pos)))


def bracket(color, length=14, w=2):
    """Accent corner bracket (top-left) as background layers (list entries)."""
    return [("linear-gradient(to right, %s, %s)" % (color, color), "%dpx %dpx" % (length, w), "left top"),
            ("linear-gradient(to bottom, %s, %s)" % (color, color), "%dpx %dpx" % (w, length), "left top")]


def layers(*ls):
    """Join several (image, size, position) layer lists into declarations."""
    flat = [x for l in ls for x in l]
    return ("background-image: %s; background-size: %s; background-position: %s; "
            "background-repeat: no-repeat;" % (", ".join(f[0] for f in flat),
                                              ", ".join(f[1] for f in flat),
                                              ", ".join(f[2] for f in flat)))


def hb_bg(accent, line2, line):
    """Headerbar layers: accent corner bracket + bottom rule fading out."""
    rule = [("linear-gradient(to right, %s, %s)" % (line2, line), "100% 1px", "left bottom")]
    return layers(bracket(accent), rule)


# Same geometry as the compositor's titlebar buttons (compositor/src/decoration.c,
# theme.h): a 30x22 cell, a 10 px icon in 1.5 px strokes on whole-pixel centres.
BTN_W, BTN_H = 30, 22
GLYPHS = {
    "min": "<path d='M10.25 15.25H20.25'/>",
    "max": "<rect x='10.25' y='6.25' width='10' height='10'/>",
    "restore": "<rect x='10.25' y='9.25' width='7' height='7'/><path d='M13.25 9.25V6.25H20.25V13.25H17.25'/>",
    "close": "<path d='M10.25 6.25L20.25 16.25M20.25 6.25L10.25 16.25'/>",
}


# libadwaita resets window-control buttons with a very specific selector; ours must out-weigh it
WCB = "button.image-button:not(.raised):not(.suggested-action):not(.destructive-action):not(.opaque)"
ASSETS = {}   # filename -> svg text, written next to each gtk.css by build()


def svg_btn(kind, color, opacity=1.0, hover=None):
    """A window button as an SVG asset file, drawn like the compositor's: the icon,
    and when `hover` is (tint, tint_alpha, bracket) a tinted box with corner
    brackets top-left and bottom-right.
    (GTK3's CSS parser does not load data: URIs, so it is a relative file.)"""
    c = hexc(parse_css(color))
    box = ""
    if hover:
        tint, alpha, brk = (hexc(parse_css(v)) if isinstance(v, str) else v for v in hover)
        box = ("<rect x='2' y='0' width='26' height='22' fill='%s' fill-opacity='%.2f'/>"
               "<path fill='%s' d='M2 0h5v1.5H3.5V5H2zM28 22h-5v-1.5h3.5V17H28z'/>" % (tint, alpha, brk))
    svg = ("<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 %d %d'>%s"
           "<g fill='none' stroke='%s' stroke-opacity='%.2f' stroke-width='1.5' stroke-linecap='square'>%s</g></svg>"
           % (BTN_W, BTN_H, BTN_W, BTN_H, box, c, opacity, GLYPHS[kind]))
    name = "btn-%s-%s%s.svg" % (kind, c[1:], "-hover-" + brk[1:] if hover else "")
    ASSETS[name] = svg
    return 'url("assets/%s")' % name


def titlebuttons(ns, roots, btn="button"):
    """CSS giving each window-control button its SVG per state.
    GtkImage ignores -gtk-icon-source when it has an icon-name, so the glyph is
    the button's background-image and the stock icon is made invisible.
    roots: container selectors ('headerbar', '.titlebar', 'windowcontrols')."""
    out = []
    tail = "background-repeat: no-repeat; background-position: center; background-size: %dpx %dpx;" % (BTN_W, BTN_H)
    for kind, cls in (("min", "minimize"), ("max", "maximize"), ("close", "close")):
        tint, alpha, brk = (ns["bad"], .30, ns["bad"]) if cls == "close" else (ns["fg"], .16, ns["accent"])
        hot = lambda k: svg_btn(k, tint, 1.0, (tint, alpha, brk))
        rules = (("", lambda k: svg_btn(k, ns["fg"], .75)), (":hover", hot), (":active", hot),
                 (":backdrop", lambda k: svg_btn(k, ns["dim"], .75)), (":backdrop:hover", hot))
        for suffix, draw in rules:
            sel = ", ".join("%s %s.%s%s" % (r, btn, cls, suffix) for r in roots)
            out.append("%s { background-image: %s; %s }" % (sel, draw(kind), tail))
            if cls == "maximize":
                sel = ", ".join(".maximized %s %s.maximize%s" % (r, btn, suffix) for r in roots)
                out.append("%s { background-image: %s; %s }" % (sel, draw("restore"), tail))
    return "\n".join(out)


def render(text, ns):
    env = dict(ns, WCB=WCB, titlebuttons=lambda roots, btn="button": titlebuttons(ns, roots, btn), chamfer=chamfer, bracket=bracket, layers=layers, hb_bg=hb_bg,
               svg_btn=svg_btn, mix=mix, tr=tr, hexc=hexc, rgba=rgba)
    return re.sub(r"\{\{(.*?)\}\}", lambda m: str(eval(m.group(1).strip(), {}, env)), text, flags=re.S)


INDEX = """[Desktop Entry]
Type=X-GNOME-Metatheme
Name={name}
Comment=Ultimit (Altimit-style) GTK theme, {Name} skin. GENERATED by build-gtk.py
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme={name}
IconTheme=Adwaita
CursorTheme=Adwaita
"""


# libadwaita's stylesheet, re-imported by the GTK4 theme: Ubuntu's libadwaita
# is Yaru-patched; upstream (Flathub runtimes, libadwaita >= 1.6) ships one
# gtk.css that follows the colour scheme through media queries.
def adw_import(scheme, flatpak):
    if flatpak:
        return "resource:///org/gnome/Adwaita/styles/gtk.css"
    return "resource:///org/gnome/Adwaita/styles/main-%s-yaru-default.css" % scheme


def build(out, tname, skin, flatpak=False):
    ns = palette(skin)
    ns["tname"] = tname
    ns["adw_import"] = adw_import(ns["scheme"], flatpak)
    d = os.path.join(out, tname)
    for sub, src in (("gtk-3.0", "gtk-3.0.css.in"), ("gtk-4.0", "gtk-4.0.css.in")):
        os.makedirs(os.path.join(d, sub), exist_ok=True)
        with open(os.path.join(TPL, src)) as f:
            css = render(f.read(), ns)
        # radius resets: appended last so they win at equal specificity
        rad = os.path.join(TPL, src.replace(".css.in", "-radius.css"))
        if os.path.exists(rad):
            css += "\n" + open(rad).read()
        with open(os.path.join(d, sub, "gtk.css"), "w") as f:
            f.write(css)
        os.makedirs(os.path.join(d, sub, "assets"), exist_ok=True)
        for fn, svg in ASSETS.items():
            with open(os.path.join(d, sub, "assets", fn), "w") as f:
                f.write(svg)
        ASSETS.clear()
    with open(os.path.join(d, "index.theme"), "w") as f:
        f.write(INDEX.format(name=tname, Name=NAMES[skin]))


def current_skin():
    p = os.path.expanduser("~/.config/ultimit/shell.json")
    try:
        s = json.load(open(p)).get("skin", "mine")
        return s if s in SKINS else "mine"
    except Exception:
        return "mine"


def main(argv):
    if not argv or argv[0].startswith("-"):
        sys.exit(__doc__)
    out, alias, only = argv[0], None, None
    if "--alias" in argv:
        alias = argv[argv.index("--alias") + 1]
    if "--only" in argv:
        only = argv[argv.index("--only") + 1]
    flatpak = "--flatpak" in argv
    alias = alias if alias in SKINS else current_skin()
    for skin in SKINS:
        if only and skin != only:
            continue
        build(out, "Ultimit-" + NAMES[skin], skin, flatpak)
    if not only:
        build(out, "Ultimit", alias, flatpak)
    print("built %d themes in %s (Ultimit = %s)" % (len(SKINS) + 1, out, alias))


if __name__ == "__main__":
    main(sys.argv[1:])
