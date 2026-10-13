#!/usr/bin/python3 -I
"""clip.py - clipboard history for Ultimit (Super+V). One JSON object on stdout, except `watch`.

  clip.py watch          run for the session: `wl-paste --watch clip.py add` (restarted by the shell)
  clip.py add            called by wl-paste on every clipboard change; records it
  clip.py list           {"items": [{id, kind, text, file, time, pinned, bytes}]}, newest first
  clip.py copy ID        put an item back on the clipboard (and move it to the top)
  clip.py pin ID on|off  pinned items survive "Clear" and new logins
  clip.py delete ID
  clip.py clear          everything except pinned items

Text and images (PNG) are kept, like Windows' clipboard history: the newest 50 plus anything
pinned, in ~/.local/share/ultimit/clipboard/. Copies that password managers mark as secret
(CLIPBOARD_STATE=sensitive, x-kde-passwordManagerHint) are never stored. Each new login starts
with only the pinned items.

Test hooks (normal user only): CLIP_DIR=<dir>, CLIP_WL_PASTE / CLIP_WL_COPY=<programs>.
"""
import fcntl
import hashlib
import json
import os
import subprocess
import sys
import time

_dev = os.getuid() != 0
DIR = (_dev and os.environ.get("CLIP_DIR")) or os.path.join(
    os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "ultimit", "clipboard")
WL_PASTE = (_dev and os.environ.get("CLIP_WL_PASTE")) or "wl-paste"
WL_COPY = (_dev and os.environ.get("CLIP_WL_COPY")) or "wl-copy"
INDEX = os.path.join(DIR, "index.json")
LOCK = os.path.join(DIR, ".lock")
KEEP = 50
MAX_TEXT = 1 << 20          # 1 MB of text
MAX_IMAGE = 16 << 20        # 16 MB PNG
PREVIEW = 4000              # characters of a text item kept in the list
SECRET_TYPES = {"x-kde-passwordManagerHint"}
TEXT_TYPES = ("text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "TEXT", "STRING")


def out(o, rc=0):
    sys.stdout.write(json.dumps(o))
    sys.stdout.flush()
    return rc


class Store:
    """index.json under an exclusive lock; text items inline, images (and long text) as files."""

    def __enter__(self):
        os.makedirs(DIR, mode=0o700, exist_ok=True)
        self.lock = open(LOCK, "w")
        fcntl.flock(self.lock, fcntl.LOCK_EX)
        try:
            with open(INDEX) as f:
                self.d = json.load(f)
        except (OSError, ValueError):
            self.d = {}
        self.d.setdefault("items", [])
        self.d.setdefault("session", "")
        self.dirty = False
        return self

    def __exit__(self, *exc):
        if self.dirty:
            tmp = INDEX + ".tmp"
            with open(tmp, "w") as f:
                json.dump(self.d, f)
            os.chmod(tmp, 0o600)
            os.replace(tmp, INDEX)
        self.lock.close()

    @property
    def items(self):
        return self.d["items"]

    def find(self, iid):
        return next((i for i in self.items if i["id"] == iid), None)

    def drop(self, it):
        self.items.remove(it)
        if it.get("file"):
            try:
                os.unlink(os.path.join(DIR, it["file"]))
            except OSError:
                pass
        self.dirty = True

    def push(self, it):
        """Newest first; an identical item moves to the top (keeping its pin)."""
        old = self.find(it["id"])
        if old:
            self.items.remove(old)
            it["pinned"] = old.get("pinned", False)
        self.items.insert(0, it)
        unpinned = [i for i in self.items if not i.get("pinned")]
        for extra in unpinned[KEEP:]:
            self.drop(extra)
        self.dirty = True

    def new_login(self):
        """A new login keeps only the pinned items."""
        sid = os.environ.get("XDG_SESSION_ID", "")
        if sid and self.d["session"] != sid:
            for it in [i for i in self.items if not i.get("pinned")]:
                self.drop(it)
            self.d["session"] = sid
            self.dirty = True


def run(argv, data=None, timeout=10):
    try:
        p = subprocess.run(argv, input=data, capture_output=True, timeout=timeout)
        return p.returncode, p.stdout
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return 1, b""


def add():
    sys.stdin.buffer.read()   # wl-paste hands us its pick of the data; we choose the type ourselves
    if os.environ.get("CLIPBOARD_STATE") in ("sensitive", "clear", "nil"):
        return 0
    rc, raw = run([WL_PASTE, "--list-types"])
    types = raw.decode("utf-8", "replace").split()
    if rc != 0 or not types or SECRET_TYPES & set(types):
        return 0
    if "image/png" in types:
        rc, data = run([WL_PASTE, "--no-newline", "--type", "image/png"], timeout=20)
        if rc != 0 or not data or len(data) > MAX_IMAGE:
            return 0
        h = hashlib.sha256(data).hexdigest()[:20]
        with Store() as s:
            path = os.path.join(DIR, h + ".png")
            if not os.path.exists(path):
                with open(path, "wb") as f:
                    f.write(data)
                os.chmod(path, 0o600)
            s.push({"id": h, "kind": "image", "file": h + ".png", "text": "", "bytes": len(data),
                    "time": int(time.time())})
        return 0
    ttype = next((t for t in TEXT_TYPES if t in types), None) or next((t for t in types if t.startswith("text/")), None)
    if not ttype:
        return 0
    rc, data = run([WL_PASTE, "--no-newline", "--type", ttype])
    if rc != 0 or not data.strip() or len(data) > MAX_TEXT:
        return 0
    text = data.decode("utf-8", "replace")
    h = hashlib.sha256(data).hexdigest()[:20]
    with Store() as s:
        it = {"id": h, "kind": "text", "text": text[:PREVIEW], "bytes": len(data), "time": int(time.time()), "file": ""}
        if len(text) > PREVIEW:   # the list shows the start; the whole text waits in a file
            it["file"] = h + ".txt"
            path = os.path.join(DIR, it["file"])
            with open(path, "wb") as f:
                f.write(data)
            os.chmod(path, 0o600)
        s.push(it)
    return 0


def copy(iid):
    with Store() as s:
        it = s.find(iid)
        if not it:
            return out({"ok": False, "error": "no such item"}, 1)
        if it.get("file"):
            with open(os.path.join(DIR, it["file"]), "rb") as f:
                data = f.read()
        else:
            data = it["text"].encode()
        argv = [WL_COPY] + (["--type", "image/png"] if it["kind"] == "image" else [])
        it["time"] = int(time.time())
        s.push(it)
    # wl-copy forks to keep serving the data; let it go without waiting on its pipes
    try:
        p = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
        p.stdin.write(data)
        p.stdin.close()
        rc = p.wait(timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        rc = 1
    return out({"ok": rc == 0, "kind": it["kind"]})


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    arg = argv[2] if len(argv) > 2 else ""
    if cmd == "add":
        return add()
    if cmd == "watch":
        with Store() as s:
            s.new_login()
        os.execvp(WL_PASTE, [WL_PASTE, "--watch", sys.executable, "-I", os.path.abspath(__file__), "add"])
    if cmd == "list":
        with Store() as s:
            items = [dict(i, file=os.path.join(DIR, i["file"]) if i.get("file") else "") for i in s.items]
        return out({"ok": True, "items": items})
    if cmd == "copy":
        return copy(arg)
    if cmd in ("pin", "delete"):
        with Store() as s:
            it = s.find(arg)
            if not it:
                return out({"ok": False, "error": "no such item"}, 1)
            if cmd == "pin":
                it["pinned"] = (argv[3] if len(argv) > 3 else "on") == "on"
                s.dirty = True
            else:
                s.drop(it)
        return out({"ok": True})
    if cmd == "clear":
        with Store() as s:
            for it in [i for i in s.items if not i.get("pinned")]:
                s.drop(it)
        return out({"ok": True})
    return out({"ok": False, "error": "usage: clip.py watch|add|list|copy ID|pin ID on|off|delete ID|clear"}, 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
