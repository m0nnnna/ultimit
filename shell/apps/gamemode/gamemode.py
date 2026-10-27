#!/usr/bin/env python3
"""gamemode.py - system side of Ultimit's Game Mode (GameMode.qml drives it).

  gamemode.py power on [--owner PID]   switch power-profiles-daemon to "performance", remembering the
                                       previous profile in <state>/gamemode.json; a watcher restores it
                                       if the owner (the shell) dies
  gamemode.py power off                restore the remembered profile (no-op without a state file)
  gamemode.py power restore-stale      same as off; the shell runs it at startup
  gamemode.py power status             print the state file (JSON) or "{}"
  gamemode.py running                  print "1 <game id>" when a game started through ultimit-game-run
                                       is alive, else "0"; also cleans markers of dead games
  gamemode.py mark [--id ID] [--pid P] ultimit-game-run records its (exec'd, so same) pid here

Never an error: without powerprofilesctl / a "performance" profile everything is skipped silently
(exit 0). Environment (tests; also keeps a nested devbox off the real power settings):
  ULTIMIT_STATE_DIR      state directory (default ~/.local/state/ultimit)
  ULTIMIT_FAKE_PPD=FILE  fake daemon: FILE holds the current profile; sets write it, calls are logged to FILE.log
  ULTIMIT_FAKE_PPD_LIST  profiles the fake offers (default "power-saver balanced performance")
  ULTIMIT_DEVBOX=1       without ULTIMIT_FAKE_PPD the power commands do nothing
  --dry-run / ULTIMIT_DRY_RUN=1   print what would be done, change nothing
"""
import json
import os
import shutil
import subprocess
import sys
import time

TARGET = "performance"


def state_dir():
    return os.environ.get("ULTIMIT_STATE_DIR") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "ultimit")


def state_file():
    return os.path.join(state_dir(), "gamemode.json")


def dry():
    return os.environ.get("ULTIMIT_DRY_RUN") == "1"


# ---------- power-profiles-daemon (or the fake) ----------
def fake():
    return os.environ.get("ULTIMIT_FAKE_PPD") or ""


def backend_enabled():
    if fake():
        return True
    if os.environ.get("ULTIMIT_DEVBOX") == "1":
        return False
    return shutil.which("powerprofilesctl") is not None


def ppd_list():
    if fake():
        return os.environ.get("ULTIMIT_FAKE_PPD_LIST", "power-saver balanced performance").split()
    try:
        out = subprocess.run(["powerprofilesctl", "list"], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    names = []
    for line in out.splitlines():
        line = line.strip().lstrip("*").strip()
        if line.endswith(":") and " " not in line[:-1]:
            names.append(line[:-1])
    return names


def ppd_get():
    if fake():
        try:
            with open(fake()) as f:
                return f.read().strip()
        except OSError:
            return ""
    try:
        return subprocess.run(["powerprofilesctl", "get"], capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def ppd_set(name):
    if dry():
        print("DRYRUN powerprofilesctl set " + name)
        return True
    if fake():
        with open(fake(), "w") as f:
            f.write(name + "\n")
        with open(fake() + ".log", "a") as f:
            f.write("set " + name + "\n")
        return True
    try:
        return subprocess.run(["powerprofilesctl", "set", name], capture_output=True, timeout=5).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


# ---------- state file ----------
def read_state():
    try:
        with open(state_file()) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def write_state(d):
    os.makedirs(state_dir(), exist_ok=True)
    tmp = state_file() + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f)
    os.replace(tmp, state_file())


def clear_state():
    try:
        os.remove(state_file())
    except OSError:
        pass


def power_on(owner=0):
    if not backend_enabled():
        return 0
    st = read_state()
    # already on, or stale from a crash: keep the profile from before the first switch
    prev = st.get("prev") or ppd_get()
    if TARGET not in ppd_list() or not prev:
        return 0
    if dry():
        print("DRYRUN would remember %r and set %s" % (prev, TARGET))
        ppd_set(TARGET)
        return 0
    write_state({"prev": prev, "owner": owner, "since": int(time.time())})
    if prev != TARGET:
        ppd_set(TARGET)
    if owner:
        spawn_watcher(owner)
    return 0


def power_off():
    st = read_state()
    if not st:
        return 0
    prev = st.get("prev")
    # only if nobody changed the profile meanwhile
    if backend_enabled() and prev and prev != TARGET and ppd_get() == TARGET:
        ppd_set(prev)
    if not dry():
        clear_state()
    return 0


def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError):
        return False


def spawn_watcher(owner):
    subprocess.Popen([sys.executable, os.path.abspath(__file__), "watch", str(owner)],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True, env=os.environ)


def watch(owner, interval=2.0):
    """Restore the profile once the owner is gone (shell crash / kill) or the state file is cleared."""
    while alive(owner) and read_state().get("owner") == owner:
        time.sleep(interval)
    if read_state().get("owner") == owner:
        power_off()
    return 0


# ---------- games started through ultimit-game-run ----------
def marker_dir():
    return os.path.join(state_dir(), "game-run")


def starttime(pid):
    try:
        with open("/proc/%d/stat" % int(pid)) as f:
            return f.read().rsplit(")", 1)[1].split()[19]
    except (OSError, IndexError, ValueError):
        return ""


def mark(game_id="", pid=None):
    pid = pid or os.getpid()
    os.makedirs(marker_dir(), exist_ok=True)
    with open(os.path.join(marker_dir(), str(pid)), "w") as f:
        json.dump({"pid": pid, "id": game_id, "start": starttime(pid)}, f)


def running():
    """The id of a live ultimit-game-run game, or None; dead / pid-reused markers are removed."""
    found = None
    try:
        names = os.listdir(marker_dir())
    except OSError:
        return None
    for n in names:
        p = os.path.join(marker_dir(), n)
        try:
            with open(p) as f:
                d = json.load(f)
            ok = alive(d["pid"]) and (not d.get("start") or d["start"] == starttime(d["pid"]))
        except (OSError, ValueError, KeyError):
            ok = False
        if ok:
            found = d.get("id") or "game"
        else:
            try:
                os.remove(p)
            except OSError:
                pass
    return found


def main(argv):
    args = [a for a in argv if a != "--dry-run"]
    if len(args) != len(argv):
        os.environ["ULTIMIT_DRY_RUN"] = "1"
    if not args:
        print(__doc__)
        return 0
    cmd = args[0]
    if cmd == "power" and len(args) > 1:
        sub = args[1]
        if sub == "on":
            owner = int(args[args.index("--owner") + 1]) if "--owner" in args else 0
            return power_on(owner)
        if sub in ("off", "restore-stale"):
            return power_off()
        if sub == "status":
            print(json.dumps(read_state()))
            return 0
    if cmd == "watch" and len(args) > 1:
        return watch(int(args[1]))
    if cmd == "running":
        g = running()
        print("1 " + g if g else "0")
        return 0
    if cmd == "mark":
        gid = args[args.index("--id") + 1] if "--id" in args else ""
        pid = int(args[args.index("--pid") + 1]) if "--pid" in args else None
        mark(gid, pid)
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:   # never break the shell
        print("gamemode.py: %s" % e, file=sys.stderr)
        sys.exit(0)
