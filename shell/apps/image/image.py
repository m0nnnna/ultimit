#!/usr/bin/env python3
"""image.py - file helper for IMAGE, the Ultimit image viewer (stdlib only).

  image.py list <file>           JSON {ok, dir, files[], index}: the images in <file>'s folder, in DATA's
                                 name order (natural, case-insensitive), and where <file> is among them
  image.py set <file>...         JSON {ok, dir, files[], index:0}: just these files (DATA "Open" on a selection)
  image.py trash <file>          JSON {ok, err}: move to the Trash (DATA's Trash, so DATA can restore it)
  image.py dir [<dir>]           JSON {ok, dir, parent, dirs[], files[], places[], err}: the library view of
                                 <dir> (default: the Pictures folder): its images, its subfolders that hold
                                 images (dirs[]: {p, n, count, cover}) and the places to jump to
                                 (places[]: {p, n}, the ones that exist)

files[] entries: {p, n, size, mtime}. Hidden files are left out unless <file> itself is one.
"""
import sys, os, json

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data"))
import data   # natkey and the freedesktop Trash, shared with DATA

# What IMAGE shows: Qt's own readers plus qt6-image-formats-plugins / kimageformat6-plugins.
EXTS = {
    "png", "jpg", "jpeg", "jpe", "jfif", "gif", "webp", "bmp", "svg", "svgz", "ico", "tif", "tiff",
    "avif", "heic", "heif", "jxl", "tga", "psd", "xcf", "exr", "hdr", "qoi", "pbm", "pgm", "ppm", "pnm",
    "xbm", "xpm", "jp2", "dds", "ras", "pcx", "kra", "ora",
}

def out(o):
    sys.stdout.write(json.dumps(o, ensure_ascii=False) + "\n")
    sys.stdout.flush()

def is_image(name):
    return name.rpartition(".")[2].lower() in EXTS and "." in name

def entry(p):
    st = os.stat(p)
    return {"p": p, "n": os.path.basename(p), "size": st.st_size, "mtime": st.st_mtime}

def cmd_list(f):
    f = os.path.abspath(f)
    d = os.path.dirname(f)
    show_hidden = os.path.basename(f).startswith(".")
    files = []
    try:
        names = os.listdir(d)
    except OSError as ex:
        names = []
        err = ex.strerror
    else:
        err = ""
    for n in names:
        if (n.startswith(".") and not show_hidden) or not is_image(n):
            continue
        p = os.path.join(d, n)
        try:
            if not os.path.isfile(p):
                continue
            files.append(entry(p))
        except OSError:
            pass
    # the file asked for is always in the set, even with an unknown extension
    if os.path.isfile(f) and not any(e["p"] == f for e in files):
        try: files.append(entry(f))
        except OSError: pass
    files.sort(key=lambda e: data.natkey(e["n"]))
    idx = next((i for i, e in enumerate(files) if e["p"] == f), 0)
    if not os.path.isfile(f):
        files, idx, err = [], 0, err or ("Not a file" if os.path.exists(f) else "No such file")
    out({"ok": bool(files), "dir": d, "files": files, "index": idx, "err": err})

def cmd_set(paths):
    files = []
    for p in paths:
        p = os.path.abspath(p)
        try:
            if os.path.isfile(p) and not any(e["p"] == p for e in files):
                files.append(entry(p))
        except OSError:
            pass
    out({"ok": bool(files), "dir": os.path.dirname(files[0]["p"]) if files else "", "files": files, "index": 0,
         "err": "" if files else "No such file"})

def user_dir(key, fallback):
    """An XDG user dir (~/.config/user-dirs.dirs), like xdg-user-dir."""
    home = os.path.expanduser("~")
    cfg = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config"), "user-dirs.dirs")
    try:
        with open(cfg, encoding="utf-8") as f:
            for line in f:
                k, _, v = line.strip().partition("=")
                if k == "XDG_%s_DIR" % key:
                    v = v.strip('"').replace("$HOME", home)
                    if v.rstrip("/") != home:
                        return v
    except OSError:
        pass
    return os.path.join(home, fallback)

def places():
    pics = user_dir("PICTURES", "Pictures")
    cands = [(pics, "Pictures"), (os.path.join(pics, "Screenshots"), "Screenshots"),
             (os.path.join(pics, "Wallpapers"), "Wallpapers"),
             (user_dir("DOWNLOAD", "Downloads"), "Downloads"), (user_dir("DESKTOP", "Desktop"), "Desktop")]
    return [{"p": p, "n": n} for p, n in cands if os.path.isdir(p)]

def scan(d):
    """(images, subfolders) of d, hidden ones left out."""
    imgs, subs = [], []
    with os.scandir(d) as it:
        for e in it:
            if e.name.startswith("."):
                continue
            try:
                if e.is_dir():
                    subs.append(e.path)
                elif e.is_file() and is_image(e.name):
                    imgs.append(e.path)
            except OSError:
                pass
    return imgs, subs

def cmd_dir(d):
    d = os.path.abspath(d or user_dir("PICTURES", "Pictures"))
    o = {"ok": False, "dir": d, "parent": "" if d == "/" else os.path.dirname(d), "dirs": [], "files": [],
         "places": places(), "err": ""}
    try:
        imgs, subs = scan(d)
    except OSError as ex:
        o["err"] = ex.strerror or str(ex)
        out(o)
        return
    for p in imgs:
        try: o["files"].append(entry(p))
        except OSError: pass
    o["files"].sort(key=lambda e: data.natkey(e["n"]))
    # A subfolder is shown when it holds pictures; its newest one is the cover.
    for s in subs:
        try:
            si, _ = scan(s)
        except OSError:
            continue
        if not si:
            continue
        cover = max(si, key=lambda p: os.path.getmtime(p) if os.path.exists(p) else 0)
        o["dirs"].append({"p": s, "n": os.path.basename(s), "count": len(si), "cover": cover})
    o["dirs"].sort(key=lambda e: data.natkey(e["n"]))
    o["ok"] = True
    out(o)

def cmd_trash(p):
    try:
        data.Job({"items": []}).trash(p)
        out({"ok": True})
    except OSError as ex:
        out({"ok": False, "err": ex.strerror or str(ex)})

def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    if a[0] == "list": cmd_list(a[1])
    elif a[0] == "set": cmd_set(a[1:])
    elif a[0] == "trash": cmd_trash(a[1])
    elif a[0] == "dir": cmd_dir(a[1] if len(a) > 1 else "")
    else: sys.exit(__doc__)

if __name__ == "__main__":
    main()
