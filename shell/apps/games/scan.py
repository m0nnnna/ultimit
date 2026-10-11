#!/usr/bin/env python3
"""Ultimit Games helper (stdlib only).

  scan.py scan                      JSON: steam state, games (Steam + desktop + manual), tools, settings
  scan.py save '<json>'             atomically replace ~/.config/ultimit/games.json (legacy)
  scan.py set <id> '<json>'         merge keys into games[<id>]
  scan.py top <key> '<json>'        set a top-level key (sort, hintDismissed, ...)
  scan.py touch <id>                record last-launched = now
  scan.py add-manual '<json>'       add a manual game {id,name,kind,target}
  scan.py remove-manual <id>        remove a manual game (and its settings)
  scan.py plan <id> [cmd ...]       print the launch plan (JSON) without running anything
  scan.py dry-log '<json argv>'     append a "would run" line to the dry-run log

games.json keys: games{<id>: options}, manual[], sort, hintDismissed. <id> is the Steam
appid, "desktop:<desktop-file-id>" or "manual:<token>".

Environment: ULTIMIT_STEAM_ROOT (Steam root containing steamapps/), ULTIMIT_STEAM_BIN (test hook:
path of the steam binary, empty = none), ULTIMIT_DRY_RUN=1, ULTIMIT_DRY_RUN_LOG.
"""
import contextlib, fcntl, glob, json, os, re, shlex, shutil, sys, time

HOME = os.path.expanduser("~")
DATA_HOME = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "ultimit", "games.json")
DEFAULT_PREFIX = os.path.join(DATA_HOME, "ultimit", "wine", "default")
SKIP_IDS = {"228980"}
SKIP_PREFIX = ("proton", "steam linux runtime", "steamworks")
EXTRA_PATH = ":/usr/games:/usr/local/games"
DXVK_DLLS = ("d3d9.dll", "d3d11.dll", "d3d10core.dll", "dxgi.dll")
NVIDIA_ENV = {"__NV_PRIME_RENDER_OFFLOAD": "1", "__GLX_VENDOR_LIBRARY_NAME": "nvidia",
              "__VK_LAYER_NV_optimus": "NVIDIA_only", "DXVK_FILTER_DEVICE_NAME": "NVIDIA"}
INTEGRATED_ENV = {"__GLX_VENDOR_LIBRARY_NAME": "mesa", "DXVK_FILTER_DEVICE_NAME": "Intel"}
STEAM_SKIP_DESKTOP = {"steam.desktop", "com.valvesoftware.Steam.desktop", "steam-runtime.desktop"}


# ---------------------------------------------------------------- VDF / Steam

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


def steam_candidates():
    env = os.environ.get("ULTIMIT_STEAM_ROOT")
    return [env] if env else [
        os.path.join(HOME, ".local/share/Steam"),
        os.path.join(HOME, ".steam/steam"),
        os.path.join(HOME, ".var/app/com.valvesoftware.Steam/.local/share/Steam"),
    ]


def find_root():
    for c in steam_candidates():
        if c and os.path.isdir(os.path.join(c, "steamapps")):
            return os.path.realpath(c)
    return None


def steam_data_present():
    """Has Steam ever been run? (its data dir exists) - ~/.local/share/Steam or ~/.steam."""
    cands = steam_candidates() + ([] if os.environ.get("ULTIMIT_STEAM_ROOT") else [os.path.join(HOME, ".steam")])
    return any(c and os.path.isdir(c) for c in cands)


def steam_binary():
    if "ULTIMIT_STEAM_BIN" in os.environ:
        return os.environ["ULTIMIT_STEAM_BIN"]
    return which("steam")


def steam_state(root, binary):
    """missing (not installed) | setup (installed, never run) | ready."""
    if root or steam_data_present():
        return "ready"
    return "setup" if binary else "missing"


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


def scan_steam(root):
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
                "id": appid, "appid": appid, "source": "steam", "name": name, "size": num("SizeOnDisk"),
                "lastPlayed": num("LastPlayed"), "ready": bool(num("StateFlags") & 4), "library": lib,
                "compat": compat_kind(root, lib, appid, st.get("installdir", ""), mapped),
                "portrait": portrait, "header": header, "icon": "",
            })
    return out


# ---------------------------------------------------------------- desktop entries

def app_dirs():
    """applications/ dirs in precedence order: XDG_DATA_HOME, XDG_DATA_DIRS, Flatpak exports."""
    dirs = [DATA_HOME]
    dirs += [d for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if d]
    dirs += [os.path.join(DATA_HOME, "flatpak", "exports", "share"), "/var/lib/flatpak/exports/share"]
    out = []
    for d in dirs:
        a = os.path.join(d, "applications")
        if a not in out:
            out.append(a)
    return out


def parse_desktop(path):
    """The [Desktop Entry] group as a dict (unlocalised keys only), or None."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    ent, inside = {}, False
    for ln in lines:
        ln = ln.strip()
        if not ln or ln.startswith("#"):
            continue
        if ln.startswith("["):
            inside = ln == "[Desktop Entry]"
            continue
        if inside and "=" in ln:
            k, v = ln.split("=", 1)
            k = k.strip()
            if "[" not in k and k not in ent:
                ent[k] = v.strip()
    return ent if ent else None


def exec_argv(exec_line, name=""):
    """Desktop Exec= to an argv: field codes dropped, %% unescaped, flatpak @@ markers removed."""
    try:
        toks = shlex.split(exec_line)
    except ValueError:
        toks = exec_line.split()
    out = []
    for t in toks:
        if t in ("@@", "@@u"):
            continue
        if re.fullmatch(r"%[fFuUdDnNickvm]", t):
            if t == "%c" and name:
                out.append(name)
            continue
        t = t.replace("%%", "\0")
        t = re.sub(r"%[a-zA-Z]", "", t).replace("\0", "%")
        out.append(t)
    return out


def scan_desktop(steam_ids=()):
    out, seen = [], set()
    for adir in app_dirs():
        for path in sorted(glob.glob(os.path.join(adir, "**", "*.desktop"), recursive=True)):
            did = os.path.relpath(path, adir).replace(os.sep, "-")
            if did in seen:
                continue
            seen.add(did)      # first (highest precedence) wins, even if it is then skipped
            if did.startswith("ultimit-"):
                continue       # Ultimit's own apps (GAMES itself is Categories=Game)
            ent = parse_desktop(path)
            if not ent or ent.get("Type", "Application") != "Application":
                continue
            cats = [c for c in ent.get("Categories", "").split(";") if c]
            if not any("Game" in c for c in cats):
                continue
            if ent.get("NoDisplay", "").lower() == "true" or ent.get("Hidden", "").lower() == "true":
                continue
            ex = ent.get("Exec", "")
            if not ex or did in STEAM_SKIP_DESKTOP or "steam://rungameid/" in ex:
                continue
            argv = exec_argv(ex, ent.get("Name", ""))
            if not argv or os.path.basename(argv[0]) == "steam":
                continue
            if ent.get("Terminal", "").lower() == "true":
                argv = ["x-terminal-emulator", "-e"] + argv
            out.append({
                "id": "desktop:" + did, "source": "app", "kind": "desktop", "name": ent.get("Name") or did[:-8],
                "comment": ent.get("Comment", ""), "icon": ent.get("Icon", ""), "exec": argv,
                "cwd": ent.get("Path", ""), "desktopFile": path, "flatpak": argv[0] == "flatpak",
                "lastPlayed": 0, "size": 0, "ready": True, "portrait": "", "header": "",
            })
    return out


def manual_games(conf):
    out = []
    for m in conf.get("manual", []):
        if not isinstance(m, dict) or not str(m.get("id", "")).startswith("manual:") or not m.get("name"):
            continue
        kind = "wine" if m.get("kind") == "wine" else "command"
        out.append({
            "id": m["id"], "source": "app", "kind": kind, "manual": True, "name": str(m["name"]),
            "target": str(m.get("target", "")), "icon": "", "lastPlayed": 0, "size": 0, "ready": True,
            "portrait": "", "header": "",
        })
    return out


# ---------------------------------------------------------------- settings

def which(n):
    return shutil.which(n, path=os.environ.get("PATH", "") + EXTRA_PATH) or ""


def has_nvidia():
    return os.path.exists("/proc/driver/nvidia")


def normalize(d):
    d = d if isinstance(d, dict) else {}
    if not isinstance(d.get("games"), dict):
        d["games"] = {}
    if not isinstance(d.get("manual"), list):
        d["manual"] = []
    return d


def load_settings():
    try:
        with open(CONF) as f:
            return normalize(json.load(f))
    except (OSError, ValueError):
        return normalize({})


@contextlib.contextmanager
def locked():
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    with open(CONF + ".lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        yield


def write_settings(data):
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    tmp = CONF + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
    os.replace(tmp, CONF)


def update(fn):
    with locked():
        d = load_settings()
        fn(d)
        write_settings(d)


def touch(gid):
    if gid:
        update(lambda d: d["games"].setdefault(gid, {}).__setitem__("lastLaunched", int(time.time())))


def effective(g, nvidia=None):
    """Per-game options with defaults applied (same defaults as the Games window)."""
    nvidia = has_nvidia() if nvidia is None else nvidia
    g = g if isinstance(g, dict) else {}
    gpu = g.get("gpu", "discrete" if nvidia else "auto")
    gpu = {"nvidia": "discrete"}.get(gpu, gpu)
    if gpu not in ("auto", "discrete", "integrated"):
        gpu = "auto"
    res = str(g.get("scopeRes", "") or "")
    try:
        fps = int(g.get("scopeFps", 0) or 0)
    except (TypeError, ValueError):
        fps = 0
    return {
        "gpu": gpu, "gamemode": g.get("gamemode", True) is True, "overlay": g.get("overlay") is True,
        "gamescope": g.get("gamescope") is True,
        "scopeRes": res if re.fullmatch(r"\d{3,5}x\d{3,5}", res) else "",
        "scopeFps": fps if 1 <= fps <= 1000 else 0,
        "dxvk": g.get("dxvk", True) is True, "args": str(g.get("args", "") or ""),
        "env": str(g.get("env", "") or ""), "prefix": str(g.get("prefix", "") or "default") or "default",
        "lastLaunched": int(g.get("lastLaunched", 0) or 0),
    }


def parse_env(text):
    """'A=1 B="x y"' (spaces or newlines) -> {A:'1', B:'x y'}; invalid names are dropped."""
    out = {}
    try:
        toks = shlex.split(text.replace("\n", " "))
    except ValueError:
        toks = text.split()
    for t in toks:
        k, eq, v = t.partition("=")
        if eq and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k):
            out[k] = v
    return out


def split_args(text):
    try:
        return shlex.split(text)
    except ValueError:
        return text.split()


# ---------------------------------------------------------------- launch planning

def dxvk_dir():
    for c in (os.environ.get("ULTIMIT_DXVK_DIR"), os.path.join(DATA_HOME, "ultimit", "dxvk", "current"),
              "/opt/ultimit/dxvk/current"):
        if c and os.path.isdir(os.path.join(c, "x64")):
            return c
    return ""


def prefix_path(opt):
    if not opt or opt == "default":
        return DEFAULT_PREFIX
    return os.path.abspath(os.path.expanduser(opt))


def install_dxvk(prefix, src):
    """Copy DXVK's d3d9/d3d10core/d3d11/dxgi into the prefix (x64 -> system32, x32 -> syswow64,
    or system32 for a pure 32-bit prefix). Returns the list of files written."""
    win = os.path.join(prefix, "drive_c", "windows")
    sys32, wow = os.path.join(win, "system32"), os.path.join(win, "syswow64")
    try:
        with open(os.path.join(prefix, "system.reg"), errors="replace") as f:
            win32 = "#arch=win32" in f.read(512)
    except OSError:
        win32 = False
    pairs = [(os.path.join(src, "x32"), sys32)] if win32 else [(os.path.join(src, "x64"), sys32)]
    if not win32 and os.path.isdir(wow):
        pairs.append((os.path.join(src, "x32"), wow))
    done = []
    for sdir, tdir in pairs:
        os.makedirs(tdir, exist_ok=True)
        for dll in DXVK_DLLS:
            s, t = os.path.join(sdir, dll), os.path.join(tdir, dll)
            if os.path.isfile(s) and not (os.path.isfile(t) and os.path.getsize(t) == os.path.getsize(s)):
                shutil.copyfile(s, t)
                done.append(t)
    return done


def find_game(gid):
    conf = load_settings()
    if gid.startswith("manual:"):
        return next((g for g in manual_games(conf) if g["id"] == gid), None)
    if gid.startswith("desktop:"):
        return next((g for g in scan_desktop() if g["id"] == gid), None)
    return None


def plan(gid, argv=None, game=None):
    """Everything needed to launch <gid>: {id, argv, env (delta), cwd, pre[], notes[]}.
    argv given  -> wrap that command (Steam `ultimit-game-run %command%`, or an explicit command).
    otherwise   -> resolve the command from the desktop entry / manual record."""
    conf = load_settings()
    o = effective(conf["games"].get(gid))
    notes, pre, env, cwd = [], [], {}, ""
    steam = gid.isdigit()
    game = game or (None if steam else find_game(gid))
    wine = False
    if argv:
        cmd = list(argv)
    elif steam:
        raise ValueError("Steam titles launch through Steam; use `ultimit-game-run %command%` as their launch option")
    elif game is None:
        raise ValueError("unknown game: " + gid)
    elif game["kind"] == "wine":
        wine = True
        exe = os.path.expanduser(game["target"])
        cmd = [which("wine") or "wine", exe]
        cwd = os.path.dirname(os.path.abspath(exe))
        if not os.path.isfile(exe):
            notes.append("executable not found: " + exe)
        if not which("wine"):
            notes.append("wine is not installed")
    elif game["kind"] == "command":
        cmd = split_args(os.path.expanduser(game["target"])) or ["true"]
    else:
        cmd = list(game["exec"])
        cwd = game.get("cwd", "")

    if wine:
        pfx = prefix_path(o["prefix"])
        env.update({"WINEPREFIX": pfx, "WINEDEBUG": "-all", "DXVK_LOG_LEVEL": "none"})
        if not os.path.exists(os.path.join(pfx, "system.reg")):
            pre.append({"step": "wineboot", "prefix": pfx})
        if o["dxvk"]:
            src = dxvk_dir()
            if src:
                pre.append({"step": "dxvk", "prefix": pfx, "src": src})
                env["WINEDLLOVERRIDES"] = "d3d9,d3d10core,d3d11,dxgi=n,b"
            else:
                notes.append("DXVK not found (scripts/get-dxvk.sh); using Wine's own Direct3D")

    if o["gpu"] == "discrete":
        if has_nvidia():
            env.update(NVIDIA_ENV)
        else:
            notes.append("no NVIDIA driver loaded; GPU left on auto")
    elif o["gpu"] == "integrated":
        env.update(INTEGRATED_ENV)

    # Wrappers, innermost first:  gamescope -f -- gamemoderun mangohud <cmd>  (same order as the Steam launch string)
    if o["overlay"]:
        if wine:
            if which("mangohud"):
                env["MANGOHUD"] = "1"      # Vulkan layer (DXVK); 64-bit only
            else:
                notes.append("mangohud not installed, skipping overlay")
        elif which("mangohud"):
            cmd = ["mangohud"] + cmd
        else:
            notes.append("mangohud not installed, skipping overlay")
    if o["gamemode"]:
        if which("gamemoderun"):
            cmd = ["gamemoderun"] + cmd
        else:
            notes.append("gamemoderun not installed, skipping GameMode")
    if o["gamescope"]:
        if which("gamescope"):
            gs = ["gamescope", "-f"]
            if o["scopeRes"]:
                w, h = o["scopeRes"].split("x")
                gs += ["-w", w, "-h", h, "-W", w, "-H", h]
            if o["scopeFps"]:
                gs += ["-r", str(o["scopeFps"])]
            cmd = gs + ["--"] + cmd
        else:
            notes.append("gamescope not installed, skipping Gamescope")

    env.update(parse_env(o["env"]))
    extra = split_args(o["args"])
    if extra:
        # extra launch arguments go after the game's own command line
        cmd = cmd + extra

    # Flatpak: the sandbox does not inherit the environment, pass it with --env=.
    if "flatpak" in cmd and "run" in cmd:
        i = cmd.index("run")
        cmd = cmd[:i + 1] + ["--env=%s=%s" % kv for kv in env.items()] + cmd[i + 1:]
    return {"id": gid, "argv": cmd, "env": env, "cwd": cwd, "pre": pre, "notes": notes}


def dry_run():
    return os.environ.get("ULTIMIT_DRY_RUN") == "1"


def dry_log(obj):
    path = os.environ.get("ULTIMIT_DRY_RUN_LOG") or os.path.join(HOME, ".cache", "ultimit", "dry-run.log")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    line = "DRYRUN " + json.dumps(obj, sort_keys=True)
    with open(path, "a") as f:
        f.write(line + "\n")
    print(line, file=sys.stderr)


# ---------------------------------------------------------------- scan / CLI

def scan():
    root = find_root()
    conf = load_settings()
    binary = steam_binary()
    steam = scan_steam(root) if root else []
    apps = scan_desktop() + manual_games(conf)
    for g in apps:
        g["lastPlayed"] = effective(conf["games"].get(g["id"]))["lastLaunched"]
    games = steam + apps
    games.sort(key=lambda g: (-g["lastPlayed"], g["name"].lower()))
    dx = dxvk_dir()
    return {
        "steamRoot": root or "", "steamBinary": bool(binary), "steamState": steam_state(root, binary),
        "games": games,
        "tools": {"gamemode": bool(which("gamemoderun")), "mangohud": bool(which("mangohud")),
                  "gamescope": bool(which("gamescope")), "nvidia": has_nvidia(), "wine": bool(which("wine")),
                  "dxvk": bool(dx), "dxvkDir": dx},
        "winePrefix": DEFAULT_PREFIX, "home": HOME, "dryRun": dry_run(),
        "settings": conf,
    }


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "scan"
    if cmd == "scan":
        print(json.dumps(scan()))
    elif cmd == "save":
        with locked():
            write_settings(normalize(json.loads(argv[2])))
    elif cmd == "set":
        patch = json.loads(argv[3])
        update(lambda d: d["games"].setdefault(argv[2], {}).update(patch))
    elif cmd == "top":
        update(lambda d: d.__setitem__(argv[2], json.loads(argv[3])))
    elif cmd == "touch":
        touch(argv[2])
    elif cmd == "add-manual":
        m = json.loads(argv[2])
        if not (str(m.get("id", "")).startswith("manual:") and str(m.get("name", "")).strip()
                and m.get("kind") in ("wine", "command") and str(m.get("target", "")).strip()):
            sys.exit("add-manual: need id (manual:..), name, kind (wine|command) and target")
        rec = {k: str(m[k]).strip() for k in ("id", "name", "kind", "target")}
        def add(d):
            d["manual"] = [x for x in d["manual"] if x.get("id") != rec["id"]] + [rec]
            if m.get("prefix"):
                d["games"].setdefault(rec["id"], {})["prefix"] = str(m["prefix"])
        update(add)
    elif cmd == "remove-manual":
        def rm(d):
            d["manual"] = [x for x in d["manual"] if x.get("id") != argv[2]]
            d["games"].pop(argv[2], None)
        update(rm)
    elif cmd == "plan":
        print(json.dumps(plan(argv[2], argv[3:] or None), indent=2))
    elif cmd == "dry-log":
        dry_log({"direct": json.loads(argv[2])})
    else:
        sys.exit("usage: scan.py scan|save|set|top|touch|add-manual|remove-manual|plan|dry-log")


if __name__ == "__main__":
    main(sys.argv)
