#!/usr/bin/env python3
"""Evaluate Python expressions against `ultimitctl state` (used by scripts/test).

  state.py eval   EXPR            print the value (JSON for dicts/lists)
  state.py assert EXPR            exit 0 if EXPR is truthy, else print it and exit 1
  state.py save   FILE            write the state JSON to FILE
  state.py buttons PNG FX FY FW   locate titlebar buttons in a screenshot
  state.py popup BEFORE AFTER     bounding box of a popup between two screenshots

Names available in EXPR: s (whole state), out (first output), usable, full,
wins (windows, front-most first), W(id), apps(substr) -> windows whose app_id
contains substr (case-insensitive), layer(namespace), E (os.environ), I(name)
(an int from the environment), box(d) -> (x, y, w, h).
"""
import json
import os
import socket
import sys


def sock_path():
    if os.environ.get("ULTIMIT_SOCK"):
        return os.environ["ULTIMIT_SOCK"]
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
                        "ultimit-%s.sock" % os.environ["WAYLAND_DISPLAY"])


def get_state():
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as c:
        c.settimeout(5)
        c.connect(sock_path())
        c.sendall(b"state\n")
        data = b""
        while not data.endswith(b"\n"):
            chunk = c.recv(65536)
            if not chunk:
                break
            data += chunk
    return json.loads(data)


def buttons(png, fx, fy, fw):
    """Find the [ _ ] [ □ ] [ × ] buttons in a screenshot of the titlebar.

    Their glyphs are the bright columns at the right end of the titlebar row.
    Buttons are three equal-width cells (text + 8px) ending 10px from the
    frame's right edge, so span = 3*w - 8 gives w. Prints
    "min_x max_x close_x y w" (screen coordinates of each cell's centre).
    """
    from PIL import Image
    im = Image.open(png).convert("RGB")
    right = fx + fw
    y0, y1 = fy + 8, fy + 27
    lo, hi = right - 10 - 170, right - 8
    cols = []
    for x in range(max(lo, 0), min(hi, im.width)):
        n = sum(1 for y in range(y0, y1) if sum(im.getpixel((x, y))) > 160)
        if n >= 5:
            cols.append(x)
    if len(cols) < 6:
        print("none")
        return 1
    left, last = cols[0], cols[-1]
    w = round((last - left + 1 + 8) / 3)
    end = right - 10
    centres = [end - w * (3 - i) + w // 2 for i in range(3)]
    print(centres[0], centres[1], centres[2], fy + 17, w)
    return 0


def popup(before, after):
    """Bounding box of a popup that appeared between two screenshots.

    The popup's background is one flat colour; the colour whose pixel count
    grows the most is it, and the pixels of that colour that were not that
    colour before are its area. Prints "x0 y0 x1 y1" or "none".
    """
    from PIL import Image, ImageChops
    a = Image.open(before).convert("RGB")
    b = Image.open(after).convert("RGB")
    ca = dict((c, n) for n, c in a.getcolors(maxcolors=2000000))
    best, gain = None, 0
    for n, c in b.getcolors(maxcolors=2000000):
        g = n - ca.get(c, 0)
        if g > gain:
            best, gain = c, g
    if best is None or gain < 5000:
        print("none")
        return 1

    def mask(im):
        solid = Image.new("RGB", im.size, best)
        return ImageChops.difference(im, solid).convert("L").point(lambda v: 255 if v == 0 else 0)
    new = ImageChops.subtract(mask(b), mask(a))
    box = new.getbbox()
    if not box:
        print("none")
        return 1
    print(*box)
    return 0


def main(argv):
    mode = argv[0]
    if mode == "popup":
        return popup(argv[1], argv[2])
    if mode == "buttons":
        return buttons(argv[1], int(argv[2]), int(argv[3]), int(argv[4]))
    s = get_state()
    if mode == "save":
        with open(argv[1], "w") as f:
            json.dump(s, f, indent=2)
        return 0
    wins = s["windows"]
    env = {
        "s": s, "out": s["outputs"][0] if s["outputs"] else {}, "wins": wins,
        "usable": s["outputs"][0]["usable"] if s["outputs"] else {},
        "full": s["outputs"][0]["full"] if s["outputs"] else {},
        "W": lambda i: next((w for w in wins if w["id"] == int(i)), None),
        "apps": lambda a: [w for w in wins if a.lower() in w["app_id"].lower()],
        "layer": lambda n: next((l for l in s["layers"] if l["namespace"] == n), None),
        "E": os.environ, "I": lambda n: int(os.environ[n]),
        "box": lambda d: (d["x"], d["y"], d["width"], d["height"]),
    }
    expr = argv[1]
    try:
        val = eval(expr, env)
    except Exception as e:  # missing window etc. counts as false
        if mode == "eval":
            print("")
            return 1
        print("error evaluating %r: %s" % (expr, e))
        return 1
    if mode == "assert":
        if val:
            return 0
        print("%s -> %r" % (expr, val))
        return 1
    print(json.dumps(val) if isinstance(val, (dict, list)) else val)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
