#!/usr/bin/env python3
"""make-templates.py - authoring tool for the Ultimit icon theme.

Writes the SVG templates in ./templates/<context>/<name>.svg. The templates carry
placeholder colours which build-icons.py substitutes per skin:

    {accent} {fg} {dim}     outline / detail / minor strokes
    {fill} {fillop}         translucent body fill (accent colour + its alpha)
    {folder} {folderfill}   folder colour (never orange: see build-icons.py SKINS)

Style rules (kept in one place so the whole set stays consistent):
  * 48 px grid, 1.5 px strokes, miter joins, butt caps, straight segments only
  * chamfered corners instead of rounded ones; circles become octagons / hexagons
  * body fill is the accent at ~15 % alpha; details are strokes
  * motifs: hex, corner brackets (templates, generic app icons)
Run:  python3 make-templates.py     (the generated templates are committed, so
build-icons.py does not need this file)
"""
import math
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "templates")

A, F, D, FO = "{accent}", "{fg}", "{dim}", "{folder}"
SW = 1.5
icons = {}   # (context, name) -> svg text


def n(v):
    s = ("%.2f" % v).rstrip("0").rstrip(".")
    return s if s else "0"


def pts_path(pts, close=True):
    return "M" + "L".join("%s %s" % (n(x), n(y)) for x, y in pts) + ("Z" if close else "")


def cp(x, y, w, h, c=4, cs=("tr", "bl")):
    """Rectangle path with the given corners chamfered by c."""
    p = []
    p += [(x, y + c), (x + c, y)] if "tl" in cs else [(x, y)]
    p += [(x + w - c, y), (x + w, y + c)] if "tr" in cs else [(x + w, y)]
    p += [(x + w, y + h - c), (x + w - c, y + h)] if "br" in cs else [(x + w, y + h)]
    p += [(x + c, y + h), (x, y + h - c)] if "bl" in cs else [(x, y + h)]
    return pts_path(p)


def poly(cx, cy, r, k=6, rot=-90):
    return pts_path([(cx + r * math.cos(math.radians(rot + 360 * i / k)),
                      cy + r * math.sin(math.radians(rot + 360 * i / k))) for i in range(k)])


def P(d, stroke=A, fill=None, sw=None):
    s = '<path d="%s"' % d
    if fill:
        s += ' fill="%s" fill-opacity="{fillop}"' % ("{fill}" if fill == "fill" else fill)
    s += ' stroke="%s"' % stroke if stroke else ' stroke="none"'
    if sw:
        s += ' stroke-width="%s"' % sw
    return s + "/>"


def S(d, stroke=F):          # detail stroke
    return P(d, stroke)


def SOL(d, color=A):         # small solid mark
    return '<path d="%s" fill="%s" stroke="none"/>' % (d, color)


def svg(*body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48" '
            'fill="none" stroke-width="%s" stroke-linejoin="miter" stroke-linecap="butt">%s</svg>\n'
            % (SW, "".join(body)))


def add(ctx, name, *body):
    icons[(ctx, name)] = svg(*body)


# ---- 24-grid glyphs, drawn into a box at (cx, cy) scaled by k -------------------
GL = {
    "doc":      ["M7 8h10M7 12h10M7 16h10M7 20h6"],
    "download": ["M12 4v11M7 11l5 5 5-5M5 20h14"],
    "music":    ["M10 17V5l9-2v12", "M5 19l2-2.5h3l2 2.5-2 2.5H7z", "M14 17l2-2.5h3l2 2.5-2 2.5h-3z"],
    "pictures": ["M3 5h18v14H3z", "M3 17l6-6 4 4 3-3 5 5", "M15 8h2.5v2.5H15z"],
    "videos":   ["M3 5h18v14H3z", "M10 8.5l6 3.5-6 3.5z", "M3 9h2M3 15h2M19 9h2M19 15h2"],
    "share":    ["M7 12l10-6M7 12l10 6", "M3 10h4v4H3z", "M16 3h4v4h-4z", "M16 17h4v4h-4z"],
    "templates": ["M4 8V4h4M16 4h4v4M20 16v4h-4M8 20H4v-4", "M9 12h6"],
    "desktop":  ["M3 4h18v12H3z", "M9 21h6M12 16v5"],
    "home":     ["M3 12l9-8 9 8", "M6 10v10h12V10", "M10 20v-6h4v6"],
    "remote":   ["M3 8h13M12 4l4 4-4 4", "M21 16H8M12 12l-4 4 4 4"],
}


def glyph(name, cx, cy, k, color=F):
    ox, oy = cx - 12 * k, cy - 12 * k
    return ('<g transform="translate(%s %s) scale(%s)" stroke="%s" stroke-width="%s">%s</g>'
            % (n(ox), n(oy), n(k), color, n(SW / k), "".join('<path d="%s"/>' % d for d in GL[name])))


# ---- tiny block letters (5 x 6 units) for file-type tags -------------------------
LET = {
    "P": "M0 6V0H3.5L5 1.5V3L3.5 4.5H0", "D": "M0 0V6H3L5 4.5V1.5L3 0Z",
    "F": "M5 0H0V6M0 3H4", "Y": "M0 0L2.5 3L5 0M2.5 3V6", "M": "M0 6V0L2.5 3L5 0V6",
}


def word(w, cx, cy, color=F):
    wd = len(w) * 5 + (len(w) - 1) * 2.5
    x = cx - wd / 2
    out = []
    for ch in w:
        out.append('<path d="%s" transform="translate(%s %s)"/>' % (LET[ch], n(x), n(cy - 3)))
        x += 7.5
    return '<g stroke="%s">%s</g>' % (color, "".join(out))


# =============================================================== PLACES
def folder(open_=False, g=None, gcy=30):
    if open_:
        body = [P("M5 40V9H18L22 13H37V21H11Z", FO, "{folder}"),
                P("M11 21H43L38 40H5Z", FO, "{folder}")]
    else:
        body = [P("M5 9H18L22 13H40L43 16V38L40 41H8L5 38Z", FO, "{folder}"),
                S("M5 19H43", FO)]
    if g:
        body.append(glyph(g, 24, gcy, .62))
    return body


add("places", "folder", *folder())
add("places", "folder-open", *folder(True))
for nm, g in [("user-home", "home"), ("user-desktop", "desktop"), ("folder-documents", "doc"),
              ("folder-download", "download"), ("folder-music", "music"), ("folder-pictures", "pictures"),
              ("folder-videos", "videos"), ("folder-publicshare", "share"),
              ("folder-templates", "templates"), ("folder-remote", "remote")]:
    add("places", nm, *folder(g=g, gcy=30.5))


def bin_(full):
    b = [P("M10 15H38L36 43H12Z", A, "fill"),
         S("M7 15H41", A), S("M18 15V9H30V15", A),
         S("M19 22V37M24 22V37M29 22V37", F)]
    if full:
        b = [S("M15 15L17 7H24L27 11L31 8L33 15", F)] + b
    return b


add("places", "user-trash", *bin_(False))
add("places", "user-trash-full", *bin_(True))
add("places", "network-workgroup",
    P("M18 5H30V13H18Z", A, "fill"), P("M5 35H17V43H5Z", A, "fill"), P("M31 35H43V43H31Z", A, "fill"),
    S("M24 13V24M11 35V24H37V35", F), SOL("M22 22h4v4h-4z", F))

# =============================================================== DEVICES
add("devices", "drive-harddisk",
    P(cp(5, 15, 38, 22, 5, ("tl", "br")), A, "fill"),
    S("M5 22H43", D), S("M10 30H24", F), SOL("M35 28.5h4v3h-4z", A))
add("devices", "drive-removable-media",
    P(cp(17, 15, 26, 18, 4, ("tr", "bl")), A, "fill"),
    P("M5 19H17V29H5Z", F), S("M8 22V26M11 22V26", F), SOL("M35 28h4v2h-4z", A), S("M22 20H32", D))
add("devices", "media-removable",
    P(cp(11, 5, 26, 38, 6, ("tr", "bl")), A, "fill"),
    S("M17 5V12M22 5V12M27 5V12M32 5V12", F), S("M17 30H31", D))
add("devices", "drive-optical",
    P(poly(24, 24, 19, 8, -67.5), A, "fill"), P(poly(24, 24, 5, 6, -90), F),
    S("M13 15L17 11M35 33L31 37", D), S(poly(24, 24, 12, 8, -67.5), D))
add("devices", "phone",
    P(cp(13, 3, 22, 42, 5, ("tr", "bl")), A, "fill"),
    S("M13 10H35M13 37H35", D), S("M21 6.5H27", F), S("M21 41H27", F))
add("devices", "computer",
    P(cp(4, 7, 40, 26, 4, ("tr", "bl")), A, "fill"),
    S("M17 42H31M24 33V42", F), S("M9 12H14M9 12V17M39 28H34M39 28V23", D))
add("devices", "audio-headphones",
    S("M9 30V22L15 10H33L39 22V30", A),
    P(cp(5, 27, 9, 15, 3, ("tl", "br")), A, "fill"), P(cp(34, 27, 9, 15, 3, ("tr", "bl")), A, "fill"),
    S("M9 32V37M39 32V37", F))
add("devices", "input-mouse",
    P("M15 5H33L38 10V35L31 43H17L10 35V10Z", A, "fill"),
    S("M10 21H38M24 5V21", F), SOL("M22 9h4v8h-4z", F))
keys = "".join("M%s %sh4v3h-4z" % (x, y) for y in (19, 25) for x in (9, 15.5, 22, 28.5, 35))
add("devices", "input-keyboard",
    P(cp(3, 11, 42, 26, 4, ("tr", "bl")), A, "fill"), SOL(keys, F), S("M13 32H35", F))
PAD = "M3 9l3-3h12l3 3v6l-3 3h-3l-2-2h-2l-2 2H6l-3-3z"


def pad(x, y, k, extra=()):
    return ('<g transform="translate(%s %s) scale(%s)" stroke-width="%s">%s%s%s</g>'
            % (n(x), n(y), n(k), n(SW / k),
               P(PAD, A, "fill"),
               S("M8 10v4M6 12h4", F), SOL("M14.5 10h2v2h-2zM16.5 12h2v2h-2z", F)))


add("devices", "input-gaming", pad(1.2, 1.2, 1.9))
add("devices", "camera-photo",
    P("M4 14H14L17 10H31L34 14H44V39H4Z", A, "fill"),
    P(poly(24, 26, 8.5, 6, -90), F), SOL(poly(24, 26, 3.5, 6, -90), A), SOL("M37 17.5h3v2h-3z", F))
add("devices", "printer",
    P("M13 4H35V16H13Z", A, "fill"), P(cp(4, 16, 40, 18, 4, ("tr", "bl")), A, "fill"),
    P("M12 28H36V44H12Z", F), S("M16 34H32M16 38H27", D), SOL("M37 20h3v2h-3z", F))
add("devices", "battery",
    P(cp(3, 14, 37, 20, 3, ("tr", "bl")), A, "fill"), P("M40 21H45V27H40Z", A),
    SOL("M7 18h7v12H7zM16 18h7v12h-7zM25 18h7v12h-7z", A))

# =============================================================== MIMETYPES
def page(*content, fillcol="fill"):
    return [P("M10 4H29L38 13V40L34 44H10Z", A, fillcol), S("M29 4V13H38", A)] + list(content)


LINES = lambda ys, x2=33: "".join("M15 %sH%s" % (y, x2 if i < len(ys) - 1 else 26) for i, y in enumerate(ys))
add("mimetypes", "text-x-generic", *page(S(LINES([21, 26, 31, 36]))))
add("mimetypes", "text-x-script", *page(S("M16 24L22 29L16 34M25 35H33")))
add("mimetypes", "text-x-python", *page(S("M15 20H25", D), word("PY", 24, 31)))
add("mimetypes", "text-html", *page(S("M20 22L14 29L20 36M28 22L34 29L28 36M25 20L23 38")))
add("mimetypes", "text-markdown", *page(S("M15 20H25", D), word("MD", 24, 31)))
add("mimetypes", "application-json",
    *page(S("M21 21H19L17 23V27L15 29L17 31V35L19 37H21M27 21H29L31 23V27L33 29L31 31V35L29 37H27")))
add("mimetypes", "application-pdf", *page(S("M15 20H25", D), word("PDF", 24, 31)))
add("mimetypes", "image-x-generic",
    P(cp(4, 8, 40, 32, 5, ("tl", "br")), A, "fill"), S("M4 33L16 21L24 29L31 22L44 35"), SOL("M31 13h4v4h-4z", F))
add("mimetypes", "video-x-generic",
    P(cp(4, 8, 40, 32, 5, ("tl", "br")), A, "fill"), S("M10 8V40M38 8V40", D),
    P("M19 17L31 24L19 31Z", F, "fill"))
add("mimetypes", "audio-x-generic",
    P(cp(4, 8, 40, 32, 5, ("tl", "br")), A, "fill"), S("M10 24H12M16 18V30M21 13V35M26 19V29M31 15V33M36 21V27M40 24H38"))
add("mimetypes", "package-x-generic",
    P("M24 4L40 13V33L24 42L8 33V13Z", A, "fill"), S("M8 13L24 22L40 13M24 22V42", F), S("M16 8.5L32 17.5V26", D))
zip_ = "".join("M22.5 %sh3v3h-3z" % y for y in (7, 13, 19, 25))
add("mimetypes", "application-x-archive",
    *page(S(zip_, F), P("M20 31H28V39H20Z", F)))
add("mimetypes", "x-office-document",
    *page(P("M15 19H33V23H15Z", F, "fill"), S("M15 28H33M15 33H33M15 38H25")))
add("mimetypes", "x-office-spreadsheet",
    *page(S("M14 20H34V38H14ZM14 26H34M14 32H34M24 20V38"), SOL("M14 20h10v6H14z", F)))
add("mimetypes", "x-office-presentation",
    *page(P("M14 19H34V31H14Z", F), S("M18 27V24M22 27V22M26 27V25M30 27V21", A), S("M24 31V37M19 38H29")))
add("mimetypes", "font-x-generic",
    *page(S("M16 38L24 17L32 38M19 31H29")))
add("mimetypes", "application-x-firmware",
    P(cp(11, 11, 26, 26, 5, ("tr", "bl")), A, "fill"), P("M18 18H30V30H18Z", F, "fill"),
    S("M17 5V11M24 5V11M31 5V11M17 37V43M24 37V43M31 37V43M5 17H11M5 24H11M5 31H11M37 17H43M37 24H43M37 31H43", D))
add("mimetypes", "application-x-executable",
    P(cp(4, 7, 40, 34, 4, ("tr", "bl")), A, "fill"), S("M4 15H44", A),
    P(poly(24, 28, 8, 6, -90), F), SOL(poly(24, 28, 3, 6, -90), F), SOL("M8 10h3v2H8z", F))
add("mimetypes", "unknown",
    *page(S("M19 25L21 22H27L29 25V28L24 32V34"), SOL("M22.5 37h3v3h-3z", F)))

# =============================================================== APPS (Ultimit's own)
def brackets(c=D):
    return S("M2 8V2H8M40 2H46V8M46 40V46H40M8 46H2V40", c)


add("apps", "ultimit-data",
    P("M24 5L40 14V34L24 43L8 34V14Z", A, "fill"), S("M8 14L24 23L40 14M24 23V43", F),
    SOL(poly(24, 23, 2.4, 6, -90), A))
add("apps", "ultimit-memo",
    P("M11 6H29L38 15V41H11Z", A, "fill"), S("M29 6V15H38", A),
    S("M16 22H33M16 28H33M16 34H24", F), SOL("M27 32h3v5h-3z", A))
kk = "".join("M%s %sh5v4.5h-5z" % (x, y) for y in (23.5, 30, 36.5) for x in (14.5, 21.5, 28.5))
add("apps", "ultimit-calc",
    P(cp(9, 5, 30, 38, 5, ("tr", "bl")), A, "fill"), P("M14 10H34V17H14Z", F),
    S(kk, F))
add("apps", "ultimit-settings",
    P(cp(7, 7, 34, 34, 5, ("tl", "br")), A, "fill"),
    S("M13 17H35M13 24H35M13 31H35", D),
    P("M17 14H21V20H17Z", A, "fill"), P("M28 21H32V27H28Z", A, "fill"), P("M21 28H25V34H21Z", A, "fill"))
add("apps", "ultimit-games",
    pad(1.2, 1.2, 1.9))
add("apps", "ultimit-shares",
    P("M6 14V9H18L22 14H42V39H6Z", A, "fill"), S("M6 18H42", A),
    S("M24 29H31M31 29L36 25M31 29L36 33", F), SOL("M20 27h4v4h-4z", A), SOL("M35 23h4v4h-4zM35 31h4v4h-4z", F))
add("apps", "ultimit-broadcast",
    P(cp(18, 6, 12, 20, 4, ("tl", "br")), A, "fill"), S("M12 21V27L18 33H30L36 27V21"),
    S("M24 33V40M17 40H31"), S("M21 12H27M21 16H27M21 20H27", F), SOL("M38 8h4v4h-4z", A), SOL("M6 8h4v4H6z", F))
add("apps", "ultimit-firewall",
    P("M24 5L40 11V24L24 43L8 24V11Z", A, "fill"), S("M8 24H40M16 15V24M32 15V24M24 24V34", F),
    S("M8 15H40", A))
add("apps", "ultimit-terminal",
    P(cp(5, 8, 38, 32, 4, ("tr", "bl")), A, "fill"), S("M5 16H43", A),
    S("M12 22L18 27L12 32", F), S("M22 33H32", A), SOL("M8 11h3v2H8z", F))
add("apps", "web-browser",
    brackets(),
    P(poly(24, 24, 18, 8, -67.5), A, "fill"),
    S("M6 24H42M10 15H38M10 33H38", D), S("M24 6L32 24L24 42L16 24Z", F))
add("apps", "application-default-icon",
    brackets(),
    P("M24 5L40 14V34L24 43L8 34V14Z", A, "fill"), P(poly(24, 24, 7, 6, -60), F, "fill"))

# =============================================================== write
def main():
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    for (ctx, name), text in sorted(icons.items()):
        d = os.path.join(OUT, ctx)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, name + ".svg"), "w") as f:
            f.write(text)
    print("wrote %d templates to %s" % (len(icons), OUT))


if __name__ == "__main__":
    main()
