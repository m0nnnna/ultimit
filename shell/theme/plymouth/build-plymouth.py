#!/usr/bin/env python3
"""build-plymouth.py - writes the Ultimit Plymouth boot splash (a "script" theme) to a directory.

  build-plymouth.py OUTDIR [--skin NAME] [--accent #rrggbb] [--config shell.json]
                           [--install-dir /usr/share/plymouth/themes/ultimit] [--preview PNG]

Needs only Pillow (apt: python3-pil). Skin palettes are read from shell/Theme.qml, the skin and
accent from shell.json ("skin", "accent"; default ~/.config/ultimit/shell.json), falling back to
the "mine" skin. Light skins (silver, paper) keep the light ink of shell/Boot.qml, since the
splash is always on pure black.

GEOMETRY CONTRACT (logical px; the splash is drawn 1:1 on screens < 2000 px tall and doubled
on taller ones; assets are rendered at 2x). Identical to the in-session overlay shell/Boot.qml.
Let C = the centre of each monitor (x0 + width/2, y0 + height/2), per monitor:

  background   pure black #000000
  emblem       84 x 84 box, centred ON C (box top-left = C - 42, C - 42). Same path as
               shell/components/Emblem.qml (48x48 box scaled by 84/48, so the 1.2 stroke is
               1.2 * 84/48 = 2.1 px). Ink = skin fg. Stroke-draws over 1.4 s (dash length =
               draw * 300 user units per contour, exactly like Emblem.qml's dashOn).
  wordmark     "[ ULTIMIT ]", Michroma 30 px, letter spacing 6 px after every glyph (also the
               last), ink colour; the text item's TOP is C.y + 42 + 18 = C.y + 60 (18 px below
               the emblem box) and it is centred on C.x including the trailing 6 px spacing.
               Text box height WM_H (printed below, ~ ascent+descent of Michroma 30).
               Fades in from t = 1.1 s over 0.6 s.
  progress     2 px high, 240 px wide line, accent colour, soft glow (14 px). Top edge at
  line         C.y + 60 + WM_H + 28. Fills from its centre outward. Faint track (ink, 14 %).
               Fades in at t = 1.5 s. Not part of the greeter (greeter just omits it).
  breathing    after the draw-in the emblem gets a slow (4.5 s) glow pulse.
  password     prompt text (Share Tech Mono 14 px) top at lineTop + 2 + 40, input line 320 px wide
               (accent, glow) 20 px below the prompt; bullets (6 px dots, 14 px pitch, max 22)
               sit just above it; status messages (dim) at monitor bottom - 64.
"""
import argparse, json, math, os, re, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
FONTS = os.path.join(ROOT, "assets", "fonts")

# ---- constants (keep in sync with the header comment and ultimit.script) ----
EMB, EMB_GAP, LINE_GAP, LINE_W, LINE_H, GLOW = 84, 18, 28, 240, 2, 14
WM_PX, WM_TRACK = 30, 6
NFRAMES = 36
DRAW_T, WM_T0, WM_T1, LINE_T0 = 1.4, 1.1, 0.6, 1.5
BREATH_T = 4.5
INPUT_W, BULLET_PITCH, MAX_BULLETS, BULLET_D = 320, 14, 22, 6
UI_PX = 14
MAXCH = 72
PAD2 = 48                      # glow padding around the emblem, at 2x
CHARSET = "".join(chr(c) for c in range(33, 127) if chr(c) not in '"\\')

FALLBACK = {"fg": "#eef1f4", "dim": "#8d949e", "accent": "#d4ebff", "light": False}


def load_skins():
    out = {}
    try:
        src = open(os.path.join(ROOT, "shell", "Theme.qml"), encoding="utf-8").read()
        blk = src[src.index("readonly property var skins"):src.index("readonly property var cur")]
        for m in re.finditer(r"(\w+):\s*\{(.*?)\n\s*\}", blk, re.S):
            body = m.group(2)
            g = lambda k: (re.search(r"\b%s:\s*\"(#[0-9a-fA-F]{6})\"" % k, body) or [None, None])[1]
            if g("fg") and g("accent"):
                out[m.group(1)] = {"fg": g("fg"), "dim": g("dim") or FALLBACK["dim"], "accent": g("accent"),
                                   "light": "light: true" in body}
    except Exception as e:  # noqa
        print("warning: could not read Theme.qml (%s), using the mine skin" % e, file=sys.stderr)
    out.setdefault("mine", FALLBACK)
    return out


def hexrgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def solid(size, rgb, mask):
    im = Image.new("RGBA", size, rgb + (0,))
    im.putalpha(mask)
    return im


# ------------------------------------------------------------------ emblem
def pt(rad, i, off):
    a = i * math.pi / 3 - math.pi / 2 + off
    return (24 + rad * math.cos(a), 24 + rad * math.sin(a))


def contours():
    hexp = lambda r, o: [pt(r, i, o) for i in range(6)]
    outer = hexp(20, 0); outer.append(outer[0])
    inner = hexp(8.5, .35); inner.append(inner[0])
    blades = [[pt(20, i, 0), pt(8.5, (i + 1) % 6, .35)] for i in range(6)]
    return [outer] + blades + [inner]   # same order as Emblem.qml's three ShapePaths


def trunc(points, length):
    if length <= 0:
        return None, False
    out, rem = [points[0]], length
    for a, b in zip(points, points[1:]):
        d = math.dist(a, b)
        if rem >= d:
            out.append(b); rem -= d
        else:
            t = rem / d
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            return out, False
    return out, True


def emblem_mask(draw, px=EMB * 2, ss=4, sw=1.2):
    n = px * ss
    u = n / 48.0
    m = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(m)
    hw = sw * u / 2
    for c in contours():
        p, _full = trunc(c, draw * 300)
        if not p or len(p) < 2:
            continue
        P = [(x * u, y * u) for x, y in p]
        for a, b in zip(P, P[1:]):
            dx, dy = b[0] - a[0], b[1] - a[1]
            L = math.hypot(dx, dy)
            nx, ny = -dy / L * hw, dx / L * hw
            d.polygon([(a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny), (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)], fill=255)
        for x, y in P[1:-1] + (P[:1] if (_full and c[0] == c[-1]) else []):
            d.ellipse([x - hw, y - hw, x + hw, y + hw], fill=255)
    return m.resize((px, px), Image.LANCZOS)


# ------------------------------------------------------------------ glow pieces
def glow_pieces(rgb):
    """vertical glow strip (scaled horizontally in the script) and left/right end caps; 2x."""
    G2, core, sig = GLOW * 2, LINE_H * 2, 8.0
    H = core + 2 * G2
    def alpha(dx, y):
        dy = max(0, abs(y + .5 - H / 2) - core / 2)
        return 0.75 * math.exp(-(dx * dx + dy * dy) / (2 * sig * sig))
    mid = Image.new("L", (2, H)); capl = Image.new("L", (G2, H))
    for y in range(H):
        for x in range(2):
            mid.putpixel((x, y), int(255 * alpha(0, y)))
        for x in range(G2):
            capl.putpixel((x, y), int(255 * alpha(G2 - x - .5, y)))
    capr = capl.transpose(Image.FLIP_LEFT_RIGHT)
    return solid(mid.size, rgb, mid), solid(capl.size, rgb, capl), solid(capr.size, rgb, capr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir")
    ap.add_argument("--skin"); ap.add_argument("--accent")
    ap.add_argument("--config", default=os.path.expanduser("~/.config/ultimit/shell.json"))
    ap.add_argument("--install-dir", default=None, help="where the theme will live (default OUTDIR)")
    ap.add_argument("--preview")
    a = ap.parse_args()
    out = os.path.abspath(a.outdir)
    os.makedirs(out, exist_ok=True)
    cfg = {}
    try:
        cfg = json.load(open(a.config))
    except Exception:
        pass
    skins = load_skins()
    name = a.skin or cfg.get("skin") or "mine"
    if name not in skins:
        name = "mine"
    sk = skins[name]
    acc = a.accent if a.accent is not None else cfg.get("accent", "")
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", acc or ""):
        acc = sk["accent"]
    ink = hexrgb("#e9edf2" if sk["light"] else sk["fg"])
    dim = hexrgb("#8d949e" if sk["light"] else sk["dim"])
    accent = hexrgb(acc)

    # emblem frames (2x), full-draw glow
    for f in range(NFRAMES):
        solid((EMB * 2,) * 2, ink, emblem_mask(f / (NFRAMES - 1))).save(os.path.join(out, "emblem-%d.png" % f))
    full = emblem_mask(1.0)
    S = EMB * 2 + 2 * PAD2
    g = Image.new("L", (S, S), 0); g.paste(full, (PAD2, PAD2))
    g = g.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(11)).point(lambda v: min(255, v * 3))
    solid((S, S), ink, g).save(os.path.join(out, "glow.png"))

    # wordmark (2x), like Qt: advance + letterSpacing after every glyph
    wf = ImageFont.truetype(os.path.join(FONTS, "Michroma-Regular.ttf"), WM_PX * 2)
    text = "[ ULTIMIT ]"
    asc, desc = wf.getmetrics()
    xs, x = [], 0.0
    for ch in text:
        xs.append(x); x += wf.getlength(ch) + WM_TRACK * 2
    ww = int(math.ceil(x / 2.0)) * 2; wh = int(math.ceil((asc + desc) / 2.0)) * 2
    m = Image.new("L", (ww, wh), 0); d = ImageDraw.Draw(m)
    for ch, cx in zip(text, xs):
        d.text((cx, asc), ch, font=wf, fill=255, anchor="ls")
    solid((ww, wh), ink, m).save(os.path.join(out, "wordmark.png"))
    WM_W2, WM_H2 = ww, wh

    # line parts
    solid((2, LINE_H * 2), accent, Image.new("L", (2, LINE_H * 2), 255)).save(os.path.join(out, "line.png"))
    solid((2, LINE_H * 2), ink, Image.new("L", (2, LINE_H * 2), 36)).save(os.path.join(out, "track.png"))
    for n, im in zip(("glow-mid", "glow-l", "glow-r"), glow_pieces(accent)):
        im.save(os.path.join(out, n + ".png"))

    # bullet + mono glyph atlas (fg and dim), one PNG per character
    bd = BULLET_D * 2
    bm = Image.new("L", (bd * 4, bd * 4), 0); ImageDraw.Draw(bm).ellipse([0, 0, bd * 4 - 1, bd * 4 - 1], fill=255)
    bm = bm.resize((bd, bd), Image.LANCZOS)
    solid((bd, bd), ink, bm).save(os.path.join(out, "bullet.png"))
    mf = ImageFont.truetype(os.path.join(FONTS, "ShareTechMono-Regular.ttf"), UI_PX * 2)
    ma, md = mf.getmetrics()
    cw = int(math.ceil(mf.getlength("M") / 2.0)) * 2; ch_ = int(math.ceil((ma + md) / 2.0)) * 2
    for i, c in enumerate(CHARSET):
        gm = Image.new("L", (cw, ch_), 0); ImageDraw.Draw(gm).text((0, ma), c, font=mf, fill=255, anchor="ls")
        solid((cw, ch_), ink, gm).save(os.path.join(out, "g%d.png" % i))
        solid((cw, ch_), dim, gm).save(os.path.join(out, "d%d.png" % i))

    wm_h = WM_H2 // 2
    script = open(os.path.join(HERE, "ultimit.script.in"), encoding="utf-8").read()
    for k, v in {"EMB": EMB, "EMB_GAP": EMB_GAP, "WM_H": wm_h, "WM_W2": WM_W2, "WM_H2": WM_H2, "LINE_GAP": LINE_GAP,
                 "LINE_W": LINE_W, "LINE_H": LINE_H, "GLOW": GLOW, "NFRAMES": NFRAMES, "DRAW_T": DRAW_T,
                 "WM_T0": WM_T0, "WM_T1": WM_T1, "LINE_T0": LINE_T0, "BREATH_T": BREATH_T, "PAD2": PAD2,
                 "GLOW_PX2": S, "INPUT_W": INPUT_W, "BULLET_PITCH": BULLET_PITCH, "MAX_BULLETS": MAX_BULLETS,
                 "BULLET_D": BULLET_D, "CELL_W2": cw, "CELL_H2": ch_, "MAXCH": MAXCH,
                 "CHARSET": CHARSET}.items():
        script = script.replace("@@%s@@" % k, str(v))
    open(os.path.join(out, "ultimit.script"), "w", encoding="utf-8").write(script)
    inst = a.install_dir or out
    open(os.path.join(out, "ultimit.plymouth"), "w").write(
        "[Plymouth Theme]\nName=Ultimit\nDescription=Ultimit boot splash (%s skin)\nModuleName=script\n\n"
        "[script]\nImageDir=%s\nScriptFile=%s/ultimit.script\n" % (name, inst, inst))
    print("Ultimit splash: skin=%s accent=%s -> %s  (WM_H=%d)" % (name, acc, out, wm_h))
    if a.preview:
        preview(out, a.preview, ink, accent, wm_h, WM_W2, WM_H2, cw, ch_)


# ------------------------------------------------------------------ preview (mirrors the script layout)
def preview(d, path, ink, accent, wm_h, wm_w2, wm_h2, cw, ch_):
    W, H = 2560, 1440
    L = lambda n: Image.open(os.path.join(d, n)).convert("RGBA")
    def half(im): return im.resize((im.width // 2, im.height // 2), Image.LANCZOS)
    def text(scr, s, x_c, y, dim=False):
        px = cw // 2
        x = x_c - len(s) * px // 2
        for c in s:
            i = CHARSET.find(c)
            if i >= 0:
                scr.alpha_composite(half(L(("d%d.png" if dim else "g%d.png") % i)), (x, y))
            x += px
    def frame(t, prog, pw=None, msg=None):
        scr = Image.new("RGBA", (W, H), (0, 0, 0, 255)); cx, cy = W // 2, H // 2
        f = min(NFRAMES - 1, int(t / DRAW_T * (NFRAMES - 1)))
        if t > DRAW_T + .3:
            ph = (t - DRAW_T - .3) / BREATH_T * 2 * math.pi
            gl = half(L("glow.png")); a = (0.5 - 0.5 * math.cos(ph)) * .55
            gl.putalpha(gl.getchannel("A").point(lambda v: int(v * a)))
            scr.alpha_composite(gl, (cx - gl.width // 2, cy - gl.height // 2))
        scr.alpha_composite(half(L("emblem-%d.png" % f)), (cx - EMB // 2, cy - EMB // 2))
        wa = max(0, min(1, (t - WM_T0) / WM_T1)); wm = half(L("wordmark.png"))
        wm.putalpha(wm.getchannel("A").point(lambda v: int(v * wa)))
        scr.alpha_composite(wm, (cx - wm.width // 2, cy + EMB // 2 + EMB_GAP))
        la = max(0, min(1, (t - LINE_T0) / .4)); ly = cy + EMB // 2 + EMB_GAP + wm_h + LINE_GAP
        if la > 0:
            tr = L("track.png").resize((LINE_W, LINE_H)); tr.putalpha(tr.getchannel("A").point(lambda v: int(v * la)))
            scr.alpha_composite(tr, (cx - LINE_W // 2, ly))
            w = int(prog * LINE_W) // 2 * 2
            if w >= 2:
                ln = L("line.png").resize((w, LINE_H)); gm = half(L("glow-mid.png")).resize((w, half(L("glow-mid.png")).height))
                parts = [(gm, (cx - w // 2, ly - GLOW)), (half(L("glow-l.png")), (cx - w // 2 - GLOW, ly - GLOW)),
                         (half(L("glow-r.png")), (cx + w // 2, ly - GLOW)), (ln, (cx - w // 2, ly))]
                for im, pos in parts:
                    im = im.copy(); im.putalpha(im.getchannel("A").point(lambda v: int(v * la))); scr.alpha_composite(im, pos)
        if pw is not None:
            py = ly + LINE_H + 40
            text(scr, pw, cx, py)
            iy = py + ch_ // 2 + 20
            scr.alpha_composite(L("line.png").resize((INPUT_W, LINE_H)), (cx - INPUT_W // 2, iy))
            n = 9; b = half(L("bullet.png"))
            for k in range(n):
                scr.alpha_composite(b, (cx - n * BULLET_PITCH // 2 + k * BULLET_PITCH + (BULLET_PITCH - BULLET_D) // 2, iy - 8 - BULLET_D))
        if msg:
            text(scr, msg, cx, H - 64, dim=True)
        return scr.convert("RGB")
    shots = [frame(.7, 0), frame(1.4 + .25, .0), frame(3.0, .35, msg="Checking file systems..."),
             frame(5.0, .7, pw="Please enter passphrase for disk root:")]
    sheet = Image.new("RGB", (W + 12, H + 12), (40, 40, 48))
    for i, s in enumerate(shots):
        sheet.paste(s.resize((W // 2, H // 2), Image.LANCZOS), (4 + (i % 2) * (W // 2 + 4), 4 + (i // 2) * (H // 2 + 4)))
    sheet.save(path)
    print("preview:", path)


if __name__ == "__main__":
    main()
