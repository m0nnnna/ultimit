#!/usr/bin/env python3
"""Evaluate Python expressions against `ultimitctl state` (used by scripts/test).

  state.py eval   EXPR            print the value (JSON for dicts/lists)
  state.py assert EXPR            exit 0 if EXPR is truthy, else print it and exit 1
  state.py save   FILE            write the state JSON to FILE
  state.py popup BEFORE AFTER     bounding box of a popup between two screenshots

Names available in EXPR: s (whole state), out (first output), O(name) (an output), usable, full,
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
        "O": lambda n: next((o for o in s["outputs"] if o["name"] == n), None),
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
