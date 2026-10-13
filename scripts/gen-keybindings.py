#!/usr/bin/python3 -I
"""Regenerate docs/keybindings.md from the running compositor's key table (`ultimitctl keys`).

  WAYLAND_DISPLAY=<a running Ultimit, e.g. the devbox> scripts/gen-keybindings.py
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HEAD = """# Ultimit keybindings

All compositor keybindings live in one table: `compositor/src/keys.c` (`bindings[]`).
Edit it to add or change a shortcut; `ultimitctl keys` prints it as JSON (for a cheat sheet),
and this page is generated from that output (`scripts/gen-keybindings.py`). "Gesture" rows are
documentation only; their behaviour is implemented elsewhere (input.c, alttab.c).
"""


def main():
    out = subprocess.run([os.path.join(ROOT, "shell/bin/ultimitctl"), "keys"], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit("ultimitctl keys failed: is an Ultimit compositor running on $WAYLAND_DISPLAY?")
    rows = json.loads(out.stdout)["bindings"]
    cats = []
    for r in rows:
        if r["category"] not in cats:
            cats.append(r["category"])
    lines = [HEAD]
    for c in cats:
        lines += ["", "## " + c, "", "| Keys | Action |", "|---|---|"]
        lines += ["| %s | %s |" % (r["keys"], r["description"]) for r in rows if r["category"] == c]
    with open(os.path.join(ROOT, "docs/keybindings.md"), "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
