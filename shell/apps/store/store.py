#!/usr/bin/python3 -I
"""store.py - the data side of STORE, the Ultimit app store over Flathub. One JSON object on stdout.

  store.py home                    picks for the front page, the categories, what is installed
  store.py search QUERY [CAT]      apps matching QUERY (any words, in name/summary/keywords/id), optionally
                                   only in category CAT (an id from `home`); QUERY "" lists a category
  store.py app ID                  one app in full (description, developer, license, screenshots, ...)
  store.py installed               installed Flatpak apps [{id, name, version, origin, size}]

Reads Flathub's AppStream data that flatpak keeps on disk (refreshed whenever flatpak updates its
remotes) and caches a small index in ~/.cache/ultimit/store/index.json, rebuilt when the AppStream
file changes. Installing and removing are plain `flatpak install/uninstall` runs in Store.qml.

Test hooks (normal user only): STORE_APPSTREAM=<appstream.xml[.gz]>, STORE_ICONS=<dir>,
STORE_CACHE=<dir>, STORE_FLATPAK=<program used instead of flatpak>.
"""
import gzip
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

_dev = os.getuid() != 0
REMOTE = "flathub"
ROOTS = ["/var/lib/flatpak/appstream/%s/x86_64/active" % REMOTE,
         os.path.expanduser("~/.local/share/flatpak/appstream/%s/x86_64/active" % REMOTE)]
APPSTREAM = (_dev and os.environ.get("STORE_APPSTREAM")) or None
ICONS = (_dev and os.environ.get("STORE_ICONS")) or None
CACHE = (_dev and os.environ.get("STORE_CACHE")) or os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "ultimit", "store")
FLATPAK = (_dev and os.environ.get("STORE_FLATPAK")) or "flatpak"
INDEX_VERSION = 3
APP_TYPES = ("desktop-application", "desktop", "console-application")
XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"

# Front page categories (AppStream main categories, in the order Windows users look for them)
CATEGORIES = [
    ("Game", "Games"), ("AudioVideo", "Music & video"), ("Graphics", "Graphics & photo"),
    ("Network", "Internet & chat"), ("Office", "Productivity"), ("Development", "Developer tools"),
    ("Education", "Education"), ("Science", "Science"), ("Utility", "Utilities"), ("System", "System"),
]
# Picks for the front page: what people setting up a gaming / streaming PC usually look for first.
PICKS = ["com.discordapp.Discord", "com.spotify.Client", "com.obsproject.Studio", "org.mozilla.firefox",
         "com.heroicgameslauncher.hgl", "net.lutris.Lutris", "com.usebottles.bottles", "com.vysp3r.ProtonPlus",
         "net.davidotek.pupgui2", "io.github.ilya_zlobintsev.LACT", "org.videolan.VLC", "org.kde.krita",
         "org.gimp.GIMP", "org.blender.Blender", "org.telegram", "org.signal.Signal",
         "org.mozilla.thunderbird", "org.libreoffice.LibreOffice", "md.obsidian.Obsidian", "com.visualstudio.code",
         "com.github.tchx84.Flatseal", "org.prismlauncher.PrismLauncher", "io.github.flattool.Warehouse",
         "com.valvesoftware.Steam"]


def out(o, rc=0):
    sys.stdout.write(json.dumps(o))
    sys.stdout.flush()
    return rc


def appstream_path():
    if APPSTREAM:
        return APPSTREAM
    for r in ROOTS:
        for name in ("appstream.xml.gz", "appstream.xml"):
            p = os.path.join(r, name)
            if os.path.exists(p):
                return p
    return None


def icon_dir():
    if ICONS:
        return ICONS
    p = appstream_path()
    return os.path.join(os.path.dirname(p), "icons") if p else ""


def text_of(el):
    """AppStream description markup (p, ul/ol/li, em, code) -> plain text with blank lines and bullets."""
    parts = []
    for child in el:
        if child.tag == "p":
            t = " ".join("".join(child.itertext()).split())
            if t:
                parts.append(t)
        elif child.tag in ("ul", "ol"):
            items = [" ".join("".join(li.itertext()).split()) for li in child if li.tag == "li"]
            parts.append("\n".join("• " + i for i in items if i))
    return "\n\n".join(parts)


def untranslated(el, tag):
    for c in el.findall(tag):
        if c.get(XML_LANG) is None:
            return c
    return None


def parse_component(el, icons):
    cid = (el.findtext("id") or "").strip()
    if not cid:
        return None
    if cid.endswith(".desktop"):
        cid = cid[:-8]
    name = untranslated(el, "name")
    summary = untranslated(el, "summary")
    desc = untranslated(el, "description")
    dev = el.find("developer")
    dname = untranslated(dev, "name") if dev is not None else None
    developer = (dname.text if dname is not None else None) or el.findtext("developer_name") or ""
    icon = ""
    for size in ("128x128", "64x64"):
        for i in el.findall("icon"):
            if i.get("type") == "cached" and i.get("width") == size.split("x")[0] and not i.get("scale"):
                p = os.path.join(icons, size, (i.text or "").strip())
                if os.path.exists(p):
                    icon = p
                    break
        if icon:
            break
    shots = []
    for s in el.findall("screenshots/screenshot"):
        imgs = [i for i in s.findall("image") if i.get("type") == "source"] or s.findall("image")
        best = None
        for i in imgs:   # the largest thumbnail no wider than 1248, else the source
            w = int(i.get("width") or 0)
            if best is None or (w <= 1248 and w > int(best.get("width") or 0)):
                best = i
        thumbs = [i for i in s.findall("image") if i.get("type") == "thumbnail" and 600 <= int(i.get("width") or 0) <= 1248]
        if thumbs:
            best = max(thumbs, key=lambda i: int(i.get("width") or 0))
        if best is not None and best.text:
            shots.append(best.text.strip())
    custom = {v.get("key"): (v.text or "") for v in el.findall("custom/value")}
    rel = el.find("releases/release")
    bundle = el.find("bundle")
    return {
        "id": cid,
        "name": (name.text or cid).strip() if name is not None else cid,
        "summary": " ".join((summary.text or "").split()) if summary is not None else "",
        "description": text_of(desc) if desc is not None else "",
        "developer": developer.strip(),
        "license": (el.findtext("project_license") or "").strip(),
        "categories": [c.text for c in el.findall("categories/category") if c.text],
        "keywords": sorted(set((k.text or "").lower() for k in el.findall("keywords/keyword")
                               if k.get(XML_LANG) is None and k.text)),
        "icon": icon,
        "screenshots": shots[:6],
        "homepage": next((u.text.strip() for u in el.findall("url") if u.get("type") == "homepage" and u.text), ""),
        "verified": custom.get("flathub::verification::verified") == "true",
        "eol": bool(custom.get("flathub::build::eol") or custom.get("flathub::eol")),
        "version": rel.get("version", "") if rel is not None else "",
        "ref": (bundle.text or "").strip() if bundle is not None and bundle.get("type") == "flatpak" else "",
        "rating": (el.find("content_rating").get("type") if el.find("content_rating") is not None else ""),
    }


def build_index(path):
    icons = icon_dir()
    opener = gzip.open if path.endswith(".gz") else open
    apps = []
    with opener(path, "rb") as f:
        for _, el in ET.iterparse(f):
            if el.tag != "component":
                continue
            if el.get("type") in APP_TYPES:
                a = parse_component(el, icons)
                if a and not a["eol"]:
                    apps.append(a)
            el.clear()
    apps.sort(key=lambda a: a["name"].lower())
    return apps


def have_remote():
    try:
        p = subprocess.run([FLATPAK, "remotes", "--columns=name"], capture_output=True, text=True, timeout=30,
                           stdin=subprocess.DEVNULL)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False
    return REMOTE in p.stdout.split()


def load_index():
    """(apps, "", "") or (None, error, fix); fix tells Store.qml what it can do about it:
    "appstream" = the remote is there but its catalogue was never downloaded (flatpak remote-add does
    not fetch it), "remote" = no Flathub remote at all."""
    path = appstream_path()
    if not path:
        if have_remote():
            return None, "Downloading Flathub's catalogue…", "appstream"
        return None, "Flathub isn't set up yet.", "remote"
    st = os.stat(path)
    key = "%s:%d:%d:%d" % (path, st.st_mtime, st.st_size, INDEX_VERSION)
    cache = os.path.join(CACHE, "index.json")
    try:
        with open(cache) as f:
            d = json.load(f)
        if d.get("key") == key:
            return d["apps"], "", ""
    except (OSError, ValueError, KeyError):
        pass
    apps = build_index(path)
    os.makedirs(CACHE, exist_ok=True)
    tmp = cache + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"key": key, "apps": apps}, f)
    os.replace(tmp, cache)
    return apps, "", ""


def card(a, installed):
    """What a list or grid shows of an app."""
    return {"id": a["id"], "name": a["name"], "summary": a["summary"], "icon": a["icon"],
            "developer": a["developer"], "verified": a["verified"], "installed": a["id"] in installed}


def installed_apps():
    try:
        p = subprocess.run([FLATPAK, "list", "--app", "--columns=application,name,version,origin,size"],
                           capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return []
    res = []
    for line in p.stdout.splitlines():
        f = line.split("\t")
        if f and f[0]:
            res.append({"id": f[0], "name": f[1] if len(f) > 1 else f[0], "version": f[2] if len(f) > 2 else "",
                        "origin": f[3] if len(f) > 3 else "", "size": f[4] if len(f) > 4 else ""})
    return res


def score(a, words):
    """0 = no match. Name hits beat keyword hits beat summary hits beat description hits. Most words
    must match somewhere ("photo editor" still finds GIMP, which never says "editor")."""
    name, summ, kw, cid = a["name"].lower(), a["summary"].lower(), " ".join(a["keywords"]), a["id"].lower()
    desc = a["description"].lower()
    total, hits = 0, 0
    for w in words:
        if name == w:
            s = 100
        elif name.startswith(w):
            s = 60
        elif re.search(r"\b" + re.escape(w), name):
            s = 40
        elif w in kw.split():
            s = 25
        elif w in name or w in cid:
            s = 20
        elif re.search(r"\b" + re.escape(w), summ) or w in kw:
            s = 10
        elif re.search(r"\b" + re.escape(w), desc):
            s = 4
        else:
            s = 0
        total += s
        hits += s > 0
    if hits == 0 or hits * 2 < len(words):
        return 0
    return total * hits // len(words) + (3 if a["verified"] else 0) + (8 if a["id"] in PICKS else 0)


def search(apps, query, cat, installed, limit=120):
    words = [w for w in re.split(r"\s+", query.lower().strip()) if w]
    pool = [a for a in apps if not cat or cat in a["categories"]]
    if not words:
        return [card(a, installed) for a in pool[:limit]], len(pool)
    scored = [(score(a, words), a) for a in pool]
    scored = [(s, a) for s, a in scored if s > 0]
    scored.sort(key=lambda t: (-t[0], t[1]["name"].lower()))
    return [card(a, installed) for _, a in scored[:limit]], len(scored)


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "installed":
        return out({"ok": True, "apps": installed_apps()})
    if cmd not in ("home", "search", "app"):
        return out({"ok": False, "error": "usage: store.py home | search QUERY [CAT] | app ID | installed"}, 2)
    apps, err, fix = load_index()
    if apps is None:
        return out({"ok": False, "error": err, "fix": fix})
    inst = {a["id"] for a in installed_apps()}
    if cmd == "home":
        by_id = {a["id"]: a for a in apps}
        picks = [card(by_id[i], inst) for i in PICKS if i in by_id]
        cats = [{"id": c, "label": l, "count": sum(1 for a in apps if c in a["categories"])} for c, l in CATEGORIES]
        return out({"ok": True, "picks": picks, "categories": cats, "total": len(apps), "installed": sorted(inst)})
    if cmd == "search":
        res, n = search(apps, argv[2] if len(argv) > 2 else "", argv[3] if len(argv) > 3 else "", inst)
        return out({"ok": True, "apps": res, "count": n})
    a = next((a for a in apps if a["id"] == (argv[2] if len(argv) > 2 else "")), None)
    if not a:
        return out({"ok": False, "error": "no such app"})
    return out({"ok": True, "app": dict(a, installed=a["id"] in inst)})


if __name__ == "__main__":
    sys.exit(main(sys.argv))
