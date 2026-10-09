#!/usr/bin/env python3
"""Ultimit Games helper (stdlib only).

  scan.py scan            print JSON: steam state, games, tools, settings
  scan.py save '<json>'   atomically write ~/.config/ultimit/games.json

Honors ULTIMIT_STEAM_ROOT (a Steam root dir containing steamapps/).
"""
import glob, json, os, re, shutil, sys

HOME = os.path.expanduser("~")
CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "ultimit", "games.json")
SKIP_IDS = {"228980"}
SKIP_PREFIX = ("proton", "steam linux runtime", "steamworks")


def parse_vdf(text):
    tok = re.compile(r'"((?:[^"\\]|\\.)*)"|([{}])')
    stack, cur, key = [], {}, None
    for m in tok.finditer(text):
        s, brace = m.group(1), m.group(2)
        if brace == "{":
            new = {}
            if key is not None:
                cur[key] = new
            stack.append(cur)
            cur, key = new, None
        elif brace == "}":
            if stack:
                cur = stack.pop()
            key = None
        elif key is None:
            key = s
        else:
            cur[key] = re.sub(r'\\(.)', r'\1', s)
            key = None
    return cur


def read_vdf(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return parse_vdf(f.read())
    except OSError:
        return {}


def find_root():
    env = os.environ.get("ULTIMIT_STEAM_ROOT")
    cands = [env] if env else [
        os.path.join(HOME, ".local/share/Steam"),
        os.path.join(HOME, ".steam/steam"),
        os.path.join(HOME, ".var/app/com.valvesoftware.Steam/.local/share/Steam"),
    ]
    for c in cands:
        if c and os.path.isdir(os.path.join(c, "steamapps")):
            return os.path.realpath(c)
    return None


def libraries(root):
    libs = [root]
    data = read_vdf(os.path.join(root, "steamapps", "libraryfolders.vdf"))
    data = data.get("libraryfolders", data)
    for k, v in data.items():
        p = v.get("path") if isinstance(v, dict) else (v if k.isdigit() else None)
        if not p:
            continue
        p = os.path.normpath(p if os.path.isabs(p) else os.path.join(root, p))
        if os.path.isdir(os.path.join(p, "steamapps")) and p not in libs:
            libs.append(p)
    return libs


def find_art(root, appid):
    """Return (portrait, header) image paths, either may be ''."""
    cache = os.path.join(root, "appcache", "librarycache")
    def first(patterns):
        for pat in patterns:
            hits = sorted(glob.glob(os.path.join(cache, pat)))
            if hits:
                return hits[0]
        return ""
    ext = "*"
    portrait = first([f"{appid}/library_600x900.{ext}", f"{appid}/*/library_600x900.{ext}",
                      f"{appid}_library_600x900.{ext}"])
    header = first([f"{appid}/header.{ext}", f"{appid}/*/header.{ext}", f"{appid}/library_header.{ext}",
                    f"{appid}/*/library_header.{ext}", f"{appid}_header.{ext}", f"{appid}/library_hero.{ext}",
                    f"{appid}/*/library_hero.{ext}", f"{appid}_library_hero.{ext}"])
    return portrait, header


def compat_kind(root, lib, appid, installdir, mapped):
    if appid in mapped or os.path.isdir(os.path.join(lib, "steamapps", "compatdata", appid)):
        return "proton"
    d = os.path.join(lib, "steamapps", "common", installdir)
    try:
        if any(n.lower().endswith(".exe") for n in os.listdir(d)):
            return "proton"
    except OSError:
        pass
    return "native"


def scan_games(root):
    cfg = read_vdf(os.path.join(root, "config", "config.vdf"))
    mapped = set()
    def walk(d):
        for k, v in d.items():
            if k == "CompatToolMapping" and isinstance(v, dict):
                mapped.update(v.keys())
            elif isinstance(v, dict):
                walk(v)
    walk(cfg)
    out, seen = [], set()
    for lib in libraries(root):
        for mf in sorted(glob.glob(os.path.join(lib, "steamapps", "appmanifest_*.acf"))):
            st = read_vdf(mf).get("AppState", {})
            appid, name = st.get("appid", ""), st.get("name", "")
            if not appid or not name or appid in seen:
                continue
            if appid in SKIP_IDS or name.lower().startswith(SKIP_PREFIX):
                continue
            seen.add(appid)
            def num(k):
                try:
                    return int(st.get(k, 0))
                except ValueError:
                    return 0
            portrait, header = find_art(root, appid)
            out.append({
                "appid": appid, "name": name, "size": num("SizeOnDisk"), "lastPlayed": num("LastPlayed"),
                "ready": bool(num("StateFlags") & 4), "library": lib,
                "compat": compat_kind(root, lib, appid, st.get("installdir", ""), mapped),
                "portrait": portrait, "header": header,
            })
    out.sort(key=lambda g: (-g["lastPlayed"], g["name"].lower()))
    return out


def which(n):
    return shutil.which(n, path=os.environ.get("PATH", "") + ":/usr/games:/usr/local/games") or ""


def load_settings():
    try:
        with open(CONF) as f:
            d = json.load(f)
            return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "scan"
    if cmd == "save":
        data = json.loads(sys.argv[2])
        os.makedirs(os.path.dirname(CONF), exist_ok=True)
        tmp = CONF + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, indent=2, sort_keys=True)
        os.replace(tmp, CONF)
        return
    root = find_root()
    res = {
        "steamRoot": root or "",
        "steamBinary": bool(which("steam")),
        "games": scan_games(root) if root else [],
        "tools": {"gamemode": bool(which("gamemoderun")), "mangohud": bool(which("mangohud")),
                  "gamescope": bool(which("gamescope")), "nvidia": os.path.exists("/proc/driver/nvidia")},
        "settings": load_settings(),
    }
    print(json.dumps(res))


main()
