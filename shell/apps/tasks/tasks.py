#!/usr/bin/env python3
"""tasks.py - backend of TASKS, the Ultimit task manager (JSON on stdout). Python standard library only.

Everything is read straight from /proc (and /sys, nvidia-smi for the GPU); nothing here needs root.
The parsers are pure functions over text, tested with fixtures/; `Sampler` keeps the previous sample so that
CPU, disk and network figures can be rates.

  tasks.py watch [SECONDS]              one JSON line per tick (default 1 s): cpu, memory, disk, net, gpu, processes
  tasks.py glance [SECONDS]             one small JSON line per tick (default 1 s): cpu %, memory %, gpu %, net rates;
                                        what the desktop's status block draws (no process list, no per-core work)
  tasks.py once                        the same, a single line (CPU shows 0: it needs two samples)
  tasks.py signal PID TERM|KILL|STOP|CONT [--force]
                                        send a signal; another user's process (EPERM) is retried through pkexec
                                        (polkit shows the password dialog). PID 1, the compositor and the shell
                                        itself need --force: the UI asks first.

A dismissed polkit prompt is {ok:false, cancelled:true}, not an error. TASKS_FAKE=1 runs against pretend
processes and a pretend GPU; signals then do nothing and succeed.

Windows are matched to processes by app id: the compositor's window list has no PID, so a window is given to
the one process whose name, executable or command matches its app id (several candidates: the one whose
command line also mentions the title; still several: none, rather than a wrong guess).
"""
import json
import os
import pwd
import re
import signal as sigmod
import subprocess
import sys
import threading
import time

SIGNALS = {"TERM": sigmod.SIGTERM, "KILL": sigmod.SIGKILL, "STOP": sigmod.SIGSTOP, "CONT": sigmod.SIGCONT}
CMD_MAX = 1000             # longer command lines are cut (the compositor's is several kB, sent every tick)
GPU_EVERY = 2.0              # seconds between nvidia-smi calls
WINDOWS_EVERY = 3.0          # seconds between `ultimitctl state` calls
NVIDIA_GPU = "name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw"
NVIDIA_APPS = "pid,used_memory"
PKEXEC_DISMISSED = (126,)    # pkexec: the person closed the dialog (127: not authorized / could not authenticate)


def fake():
    return os.environ.get("TASKS_FAKE") == "1"


def out(o):
    sys.stdout.write(json.dumps(o, separators=(",", ":")) + "\n")
    sys.stdout.flush()


# ============================================================ parsers (pure)

def parse_cpu_stat(text):
    """/proc/stat -> (total, [core, ...]); each is (busy_ticks, total_ticks). idle + iowait count as idle."""
    total, cores = (0, 0), []
    for line in text.splitlines():
        f = line.split()
        if not f or not f[0].startswith("cpu"):
            continue
        v = [int(x) for x in f[1:]]
        v += [0] * (8 - len(v))
        idle = v[3] + v[4]
        # guest time is already inside user/nice, so it is left out of the sum
        whole = sum(v[:8])
        pair = (whole - idle, whole)
        if f[0] == "cpu":
            total = pair
        else:
            cores.append(pair)
    return total, cores


def parse_meminfo(text):
    """/proc/meminfo -> {key: bytes} (the kB values are scaled; HugePages_* counts stay as they are)."""
    r = {}
    for line in text.splitlines():
        k, _, v = line.partition(":")
        f = v.split()
        if not f:
            continue
        r[k.strip()] = int(f[0]) * (1024 if len(f) > 1 and f[1] == "kB" else 1)
    return r


def memory(info):
    """meminfo dict -> what the UI draws: used = total - available (what htop calls the green bar plus buffers)."""
    total = info.get("MemTotal", 0)
    avail = info.get("MemAvailable", info.get("MemFree", 0))
    st = info.get("SwapTotal", 0)
    return {"total": total, "used": max(0, total - avail), "available": avail,
            "cached": info.get("Cached", 0) + info.get("SReclaimable", 0) - info.get("Shmem", 0),
            "swap_total": st, "swap_used": max(0, st - info.get("SwapFree", 0))}


def parse_pid_stat(text):
    """/proc/PID/stat -> dict, or None. The name is in parentheses and may itself hold spaces and parentheses."""
    a, b = text.find("("), text.rfind(")")
    if a < 0 or b < a:
        return None
    f = text[b + 2:].split()
    if len(f) < 22:
        return None
    try:
        return {"pid": int(text[:a]), "comm": text[a + 1:b], "state": f[0], "ppid": int(f[1]),
                "utime": int(f[11]), "stime": int(f[12]), "threads": int(f[17]),
                "start": int(f[19]), "rss_pages": int(f[21])}
    except ValueError:
        return None


def parse_status(text):
    """/proc/PID/status -> {name, uid, threads, rss (bytes)}; fields that are missing are left out."""
    r = {}
    for line in text.splitlines():
        k, _, v = line.partition(":")
        f = v.split()
        if not f:
            continue
        if k == "Name":
            r["name"] = v.strip()
        elif k == "Uid":
            r["uid"] = int(f[0])
        elif k == "Threads":
            r["threads"] = int(f[0])
        elif k == "VmRSS":
            r["rss"] = int(f[0]) * 1024
    return r


def parse_cmdline(raw):
    """/proc/PID/cmdline bytes -> the command line as one string ('' for kernel threads)."""
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8", "replace")
    return " ".join(x for x in raw.split("\0") if x != "").strip()


def parse_diskstats(text, whole):
    """/proc/diskstats -> (read_bytes, written_bytes) summed over the whole disks named in `whole`
    (partitions would count twice). Sectors in this file are always 512 bytes."""
    rd = wr = 0
    for line in text.splitlines():
        f = line.split()
        if len(f) >= 10 and f[2] in whole:
            rd += int(f[5]) * 512
            wr += int(f[9]) * 512
    return rd, wr


def parse_net_dev(text):
    """/proc/net/dev -> (rx_bytes, tx_bytes) over every interface but loopback."""
    rx = tx = 0
    for line in text.splitlines()[2:]:
        name, _, rest = line.partition(":")
        f = rest.split()
        if len(f) >= 9 and name.strip() != "lo":
            rx += int(f[0])
            tx += int(f[8])
    return rx, tx


def parse_loadavg(text):
    """/proc/loadavg -> ([1, 5, 15 min], running, total_tasks)."""
    f = text.split()
    run, _, tot = f[3].partition("/")
    return [float(f[0]), float(f[1]), float(f[2])], int(run), int(tot)


def parse_uptime(text):
    return float(text.split()[0])


def _num(s):
    try:
        return float(s)
    except ValueError:
        return None          # "[N/A]", "[Not Supported]"


def parse_nvidia_gpu(text):
    """nvidia-smi --query-gpu=... --format=csv,noheader,nounits -> [gpu, ...] (memory in bytes)."""
    r = []
    for line in text.strip().splitlines():
        f = [x.strip() for x in line.split(",")]
        if len(f) < 6:
            continue
        used, tot = _num(f[2]), _num(f[3])
        r.append({"name": f[0], "util": _num(f[1]), "mem_used": None if used is None else int(used * 1048576),
                  "mem_total": None if tot is None else int(tot * 1048576), "temp": _num(f[4]), "power": _num(f[5])})
    return r


def parse_nvidia_apps(text):
    """nvidia-smi --query-compute-apps=pid,used_memory ... -> {pid: bytes}."""
    r = {}
    for line in text.strip().splitlines():
        f = [x.strip() for x in line.split(",")]
        if len(f) >= 2 and f[0].isdigit() and _num(f[1]) is not None:
            r[int(f[0])] = r.get(int(f[0]), 0) + int(_num(f[1]) * 1048576)
    return r


def read_drm(root="/sys/class/drm"):
    """AMD / Intel fallback: first card with gpu_busy_percent or VRAM figures -> one gpu dict, or None."""
    try:
        names = sorted(n for n in os.listdir(root) if re.fullmatch(r"card\d+", n))
    except OSError:
        return None
    for n in names:
        d = os.path.join(root, n, "device")
        busy, used, tot = (_read_int(os.path.join(d, f)) for f in ("gpu_busy_percent", "mem_info_vram_used", "mem_info_vram_total"))
        if busy is None and tot is None:
            continue
        temp = power = None
        try:
            hw = os.path.join(d, "hwmon")
            h = os.path.join(hw, sorted(os.listdir(hw))[0])
            t = _read_int(os.path.join(h, "temp1_input"))
            p = _read_int(os.path.join(h, "power1_average"))
            temp = None if t is None else t / 1000.0
            power = None if p is None else p / 1e6
        except (OSError, IndexError):
            pass
        return {"name": _read(os.path.join(d, "product_name")).strip() or "GPU (" + n + ")",
                "util": None if busy is None else float(busy), "mem_used": used, "mem_total": tot, "temp": temp, "power": power}
    return None


def _read(path):
    try:
        with open(path, "r", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def _read_int(path):
    s = _read(path).strip()
    return int(s) if s.isdigit() else None


def app_keys(app_id):
    """A window's app id -> lowercase names a process may go by: 'io.github.x.ungoogled_chromium' -> ungoogled-chromium."""
    last = app_id.lower().split(".")[-1].replace("_", "-")
    return {last, app_id.lower().replace("_", "-")}


def proc_matches(keys, procnames):
    for k in keys:
        for n in procnames:
            if len(n) >= 4 and (n == k or k.endswith("-" + n) or k.startswith(n + "-")):
                return True
    return False


def match_windows(windows, procs):
    """Give each window to a process. windows: [{app_id, title}]; procs: [{pid, ppid, cmd, names}].
    -> {pid: {"app": app_id, "titles": [title, ...]}}. Only a main process gets one: not a child of another match
    and not a '--type=' or crashpad helper. If that leaves several, the title decides; if it cannot, no guess is made."""
    res = {}
    for w in windows:
        app, title = w.get("app_id", ""), w.get("title", "")
        if app == "":
            continue
        keys = app_keys(app)
        cand = [p for p in procs if proc_matches(keys, p["names"])]
        ids = {p["pid"] for p in cand}
        roots = [p for p in cand if p["ppid"] not in ids and "--type=" not in p["cmd"] and "crashpad" not in p["cmd"].split(" ")[0]]
        if len(roots) > 1:
            word = title.split(" ")[0].lower() if title else ""
            roots = [p for p in roots if len(word) >= 3 and word in p["cmd"].lower()]
        if len(roots) != 1:
            continue
        e = res.setdefault(roots[0]["pid"], {"app": app, "titles": []})
        if title and title not in e["titles"]:
            e["titles"].append(title)
    return res


def is_critical(pid, comm, cmd, me=None):
    """What the UI must ask about before signalling: PID 1, the compositor, the desktop shell, this app's own process."""
    if pid == 1 or pid == (me or os.getpid()):
        return True
    if comm == "ultimit":
        return True
    argv = cmd.split(" ")
    if argv and argv[0].rsplit("/", 1)[-1] in ("sh", "bash", "python3") and len(argv) > 1:
        argv = argv[1:]                                  # a script run by its interpreter
    if argv and argv[0].rsplit("/", 1)[-1] in ("ultimit-run-compositor", "ultimit-shell", "ultimit-session", "systemd",
                                                "dbus-daemon", "dbus-broker"):
        return True
    # the desktop shell is `qs -p <dir>`: a qs run from a directory, not one of the apps' own *-shell.qml files
    m = re.search(r"\bqs\b.*?\s-p\s+(\S+)", cmd)
    return bool(m and not m.group(1).endswith(".qml") and comm in ("qs", "quickshell"))


# ============================================================ sampling

class Sampler:
    """Reads /proc and keeps the last sample. tick() -> the dict the UI gets once a second.

    `root` is /proc (a test points it at fixtures); `whole` the block devices for disk rates (None: ask /sys/block);
    `extra` is shared with the slow threads: {"gpu": ..., "gpu_apps": {pid: bytes}, "windows": [...]}."""

    def __init__(self, root="/proc", whole=None, clk=None, page=None, extra=None):
        self.root = root
        self.whole = whole
        self.clk = clk or os.sysconf("SC_CLK_TCK")
        self.page = page or os.sysconf("SC_PAGE_SIZE")
        self.extra = extra if extra is not None else {}
        self.prev = None                 # previous tick: time, cpu, cores, disk, net, per-pid ticks
        self.static = {}                 # pid -> (start, cmd, exe, seen)  re-read a few times: a fork has its parent's cmdline
        self.users = {}

    def block_devices(self):
        if self.whole is not None:
            return self.whole
        try:
            return {n for n in os.listdir("/sys/block") if not re.match(r"(loop|ram|zram|dm-|sr|md)", n)}
        except OSError:
            return set()

    def user(self, uid):
        if uid not in self.users:
            try:
                self.users[uid] = pwd.getpwuid(uid).pw_name
            except KeyError:
                self.users[uid] = str(uid)
        return self.users[uid]

    def info(self, pid, st):
        """cmdline and executable of a process, cached (cheap: most processes live for many ticks)."""
        c = self.static.get(pid)
        if c is None or c[0] != st["start"] or c[3] < 3:
            try:
                with open("%s/%d/cmdline" % (self.root, pid), "rb") as f:
                    cmd = parse_cmdline(f.read())[:CMD_MAX]
            except OSError:
                cmd = ""
            try:
                exe = os.path.basename(os.readlink("%s/%d/exe" % (self.root, pid)))
            except OSError:
                exe = ""
            c = (st["start"], cmd, exe, (c[3] + 1) if c and c[0] == st["start"] else 1)
            self.static[pid] = c
        return c[1], c[2]

    def tick(self, now=None):
        now = time.monotonic() if now is None else now
        total, cores = parse_cpu_stat(_read(self.root + "/stat"))
        mem = memory(parse_meminfo(_read(self.root + "/meminfo")))
        disk = parse_diskstats(_read(self.root + "/diskstats"), self.block_devices())
        net = parse_net_dev(_read(self.root + "/net/dev"))
        try:
            load, running, ntasks = parse_loadavg(_read(self.root + "/loadavg"))
        except (IndexError, ValueError):
            load, running, ntasks = [0.0, 0.0, 0.0], 0, 0
        try:
            up = parse_uptime(_read(self.root + "/uptime"))
        except (IndexError, ValueError):
            up = 0.0

        prev = self.prev
        dt = (now - prev["t"]) if prev else 0
        pc = self.extra.get("gpu_apps") or {}
        procs, ticks, threads = [], {}, 0
        try:
            pids = [int(n) for n in os.listdir(self.root) if n.isdigit()]
        except OSError:
            pids = []
        for pid in pids:
            try:
                st = parse_pid_stat(_read(self.root + "/%d/stat" % pid))
                if not st:
                    continue
                uid = os.stat("%s/%d" % (self.root, pid)).st_uid
            except OSError:
                continue
            cmd, exe = self.info(pid, st)
            t = st["utime"] + st["stime"]
            ticks[pid] = (st["start"], t)
            pt = prev["ticks"].get(pid) if prev else None
            cpu = 0.0
            if pt and pt[0] == st["start"] and dt > 0:
                cpu = max(0.0, (t - pt[1]) / self.clk / dt * 100)
            comm = st["comm"]
            name = comm
            if cmd and len(comm) >= 15:                  # comm is cut at 15 characters: argv[0] has the whole name
                name = os.path.basename(cmd.split(" ")[0]) or comm
            threads += st["threads"]
            procs.append({"pid": pid, "ppid": st["ppid"], "name": name if cmd else "[" + comm + "]", "comm": comm,
                          "cmd": cmd, "user": self.user(uid), "uid": uid, "cpu": round(cpu, 1),
                          "rss": st["rss_pages"] * self.page, "gpu_mem": pc.get(pid), "threads": st["threads"],
                          "state": st["state"], "exe": exe})
        for pid in [p for p in self.static if p not in ticks]:
            del self.static[pid]

        # windows -> processes
        wins = self.extra.get("windows") or []
        by = match_windows(wins, [{"pid": p["pid"], "ppid": p["ppid"], "cmd": p["cmd"],
                                   "names": {p["comm"].lower(), p["exe"].lower()} | {x.lower() for x in p["cmd"].split(" ")[0].split("/")}}
                                  for p in procs]) if wins else {}
        for p in procs:
            w = by.get(p["pid"])
            p["app"] = w["app"] if w else ""
            p["titles"] = w["titles"] if w else []
            p["critical"] = is_critical(p["pid"], p["comm"], p["cmd"])
            del p["exe"]

        # rates
        def rate(cur, old):
            return [max(0, (c - o) / dt) for c, o in zip(cur, old)] if prev and dt > 0 else [0.0] * len(cur)

        def pct(cur, old):
            if not prev or cur[1] <= old[1]:
                return 0.0
            return round((cur[0] - old[0]) * 100.0 / (cur[1] - old[1]), 1)

        cpu_total = pct(total, prev["cpu"]) if prev else 0.0
        cpu_cores = [pct(c, o) for c, o in zip(cores, prev["cores"])] if prev and len(prev["cores"]) == len(cores) else [0.0] * len(cores)
        rd, wr = rate(disk, prev["disk"] if prev else disk)
        rx, tx = rate(net, prev["net"] if prev else net)
        self.prev = {"t": now, "cpu": total, "cores": cores, "disk": disk, "net": net, "ticks": ticks}
        return {"ok": True, "uptime": up, "load": load, "running": running, "ncpu": len(cores),
                "cpu": {"total": cpu_total, "cores": cpu_cores}, "mem": mem,
                "disk": {"read": round(rd), "write": round(wr)}, "net": {"rx": round(rx), "tx": round(tx)},
                "gpu": self.extra.get("gpu"), "counts": {"procs": len(procs), "threads": threads},
                "procs": procs}


class Glance:
    """The few numbers the status block graphs (CPU %, memory %, GPU %, network bytes/s), from the same
    parsers as Sampler but without the process table: a tick reads three small /proc files."""
    def __init__(self, root="/proc", extra=None):
        self.root = root
        self.extra = extra if extra is not None else {}
        self.prev = None                 # (time, cpu (busy, total), net (rx, tx))

    def read(self, name):
        return _read("%s/%s" % (self.root, name))

    def tick(self, now=None):
        now = time.monotonic() if now is None else now
        cpu, _ = parse_cpu_stat(self.read("stat"))
        net = parse_net_dev(self.read("net/dev"))
        mem = memory(parse_meminfo(self.read("meminfo")))
        pc = rx = tx = 0.0
        if self.prev:
            t0, c0, n0 = self.prev
            if cpu[1] > c0[1]:
                pc = round((cpu[0] - c0[0]) * 100.0 / (cpu[1] - c0[1]), 1)
            if now > t0:
                rx, tx = (max(0, (a - b) / (now - t0)) for a, b in zip(net, n0))
        self.prev = (now, cpu, net)
        g = self.extra.get("gpu") or {}
        vram = None
        if g.get("mem_used") is not None and g.get("mem_total"):
            vram = round(g["mem_used"] * 100.0 / g["mem_total"], 1)
        return {"ok": True, "cpu": pc, "mem": round(mem["used"] * 100.0 / mem["total"], 1) if mem["total"] else 0.0,
                "gpu": g.get("util"), "vram": vram, "rx": round(rx), "tx": round(tx)}


def read_gpu_glance():
    """One GPU dict (NVIDIA through nvidia-smi, else sysfs) or None; a single process call, no per-app query."""
    g = parse_nvidia_gpu(run_text(["nvidia-smi", "--query-gpu=" + NVIDIA_GPU, "--format=csv,noheader,nounits"]))
    return g[0] if g else read_drm()


def glance(every=1.0):
    extra = {}
    if fake():
        extra["gpu"] = {"util": 42.0, "mem_used": 3 << 30, "mem_total": 12 << 30}
    else:
        def loop():
            while True:   # the GPU is a process to ask for: every few seconds, not every tick
                extra["gpu"] = read_gpu_glance()
                time.sleep(GPU_EVERY)
        threading.Thread(target=loop, daemon=True).start()
    g = Glance(extra=extra)
    g.tick()
    nxt = time.monotonic()
    while True:
        nxt += every
        time.sleep(max(0.05, nxt - time.monotonic()))
        out(g.tick())


# ============================================================ slow sources (threads)

def run_text(cmd, timeout=3):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def read_gpu():
    """-> (gpu dict or None, {pid: vram bytes}). NVIDIA first, then AMD / Intel through sysfs."""
    g = parse_nvidia_gpu(run_text(["nvidia-smi", "--query-gpu=" + NVIDIA_GPU, "--format=csv,noheader,nounits"]))
    if g:
        apps = parse_nvidia_apps(run_text(["nvidia-smi", "--query-compute-apps=" + NVIDIA_APPS, "--format=csv,noheader,nounits"]))
        return dict(g[0], vendor="nvidia"), apps
    d = read_drm()
    return (dict(d, vendor="drm"), {}) if d else (None, {})


def read_windows():
    try:
        return [{"app_id": w.get("app_id", ""), "title": w.get("title", "")}
                for w in json.loads(run_text(["ultimitctl", "state"], 2) or "{}").get("windows", []) if w.get("mapped", True)]
    except ValueError:
        return []


def start_threads(extra):
    """Background refreshers for what is slow to ask (a process each); the tick just reads `extra`."""
    def loop(fn, every):
        while True:
            fn()
            time.sleep(every)

    def gpu():
        extra["gpu"], extra["gpu_apps"] = read_gpu()

    def wins():
        extra["windows"] = read_windows()
    for fn, every in ((gpu, GPU_EVERY), (wins, WINDOWS_EVERY)):
        threading.Thread(target=loop, args=(fn, every), daemon=True).start()


# ============================================================ pretend system (TASKS_FAKE=1)

class FakeSampler:
    """A pretend machine: 16 cores, a few dozen processes whose figures wander. Signals do nothing."""
    NAMES = [("firefox", "mino", 120), ("chromium", "mino", 90), ("code", "mino", 70), ("ultimit", "mino", 5),
             ("qs", "mino", 15), ("pipewire", "mino", 2), ("Xwayland", "mino", 3), ("steam", "mino", 20),
             ("python3", "mino", 8), ("sshd", "root", 1), ("NetworkManager", "root", 1), ("systemd-journald", "root", 2),
             ("cupsd", "root", 0), ("nvidia-persistenced", "nvidia", 0), ("obs", "mino", 40), ("blender", "mino", 30)]

    def __init__(self):
        self.n = 0
        self.disk = [0, 0]
        self.net = [0, 0]

    def tick(self, now=None):
        import math
        import random
        self.n += 1
        r = random.Random(self.n)
        procs = []
        for i, (nm, user, base) in enumerate(self.NAMES):
            pid = 1000 + i * 37
            cpu = max(0.0, base * (0.5 + 0.5 * math.sin(self.n / (3 + i))) * r.uniform(0.8, 1.2) / 6)
            procs.append({"pid": pid, "ppid": 1, "name": nm, "comm": nm[:15], "cmd": "/usr/bin/" + nm + " --fake", "user": user,
                          "uid": 1000 if user == "mino" else 0, "cpu": round(cpu, 1), "rss": (80 + base * 9 + i * 13) << 20,
                          "gpu_mem": (300 << 20) if nm in ("firefox", "obs", "blender", "chromium") else None,
                          "threads": 1 + i % 9, "state": "R" if cpu > 3 else "S",
                          "app": "org." + nm if nm in ("firefox", "chromium", "code", "steam", "obs", "blender") else "",
                          "titles": [nm.capitalize() + " window"] if nm in ("firefox", "chromium", "code", "steam", "obs", "blender") else [],
                          "critical": nm == "ultimit"})
        procs.append({"pid": 1, "ppid": 0, "name": "systemd", "comm": "systemd", "cmd": "/sbin/init", "user": "root", "uid": 0, "cpu": 0.0,
                      "rss": 12 << 20, "gpu_mem": None, "threads": 1, "state": "S", "app": "", "titles": [], "critical": True})
        cores = [round(max(0, min(100, 30 + 40 * math.sin(self.n / 4 + c) + r.uniform(-8, 8))), 1) for c in range(16)]
        used = int((9 + 2 * math.sin(self.n / 20)) * (1 << 30))
        return {"ok": True, "uptime": 90061.0 + self.n, "load": [2.1, 1.7, 1.2], "running": 3, "ncpu": 16,
                "cpu": {"total": round(sum(cores) / 16, 1), "cores": cores},
                "mem": {"total": 32 << 30, "used": used, "available": (32 << 30) - used, "cached": 6 << 30, "swap_total": 8 << 30, "swap_used": 512 << 20},
                "disk": {"read": int(r.uniform(0, 80) * 1e6), "write": int(r.uniform(0, 40) * 1e6)},
                "net": {"rx": int(r.uniform(0, 4) * 1e6), "tx": int(r.uniform(0, 1) * 1e6)},
                "gpu": {"name": "Pretend GPU", "vendor": "fake", "util": round(50 + 40 * math.sin(self.n / 5), 1), "mem_used": 3 << 30,
                        "mem_total": 12 << 30, "temp": 55.0 + self.n % 7, "power": 120.5},
                "counts": {"procs": len(procs), "threads": sum(p["threads"] for p in procs)}, "procs": procs}


# ============================================================ actions

def signal_pid(pid, name, force=False, kill=os.kill, helper=None):
    """Send TERM | KILL | STOP | CONT. Not ours (EPERM): `pkexec kill -s NAME PID`, which asks through polkit."""
    name = name.upper().removeprefix("SIG")
    if name not in SIGNALS:
        return {"ok": False, "error": "Unknown signal " + name + "."}
    if pid <= 0:
        return {"ok": False, "error": "Not a process."}
    if fake():
        return {"ok": True}
    if pid == 1 and not force:
        return {"ok": False, "error": "PID 1 is the system itself."}
    try:
        kill(pid, SIGNALS[name])
        return {"ok": True}
    except ProcessLookupError:
        return {"ok": False, "error": "That process is already gone.", "gone": True}
    except PermissionError:
        pass
    r = (helper or _pkexec)(name, pid)
    if r == 0:
        return {"ok": True}
    if r in PKEXEC_DISMISSED:
        return {"ok": False, "cancelled": True}
    return {"ok": False, "error": "Could not %s that process: the password was not accepted." % name.lower()}


def _pkexec(name, pid):
    try:
        return subprocess.run(["pkexec", "kill", "-s", name, str(pid)], stdin=subprocess.DEVNULL, timeout=120).returncode
    except (OSError, subprocess.SubprocessError):
        return 1


def watch(every=1.0):
    if fake():
        s = FakeSampler()
    else:
        extra = {}
        start_threads(extra)
        s = Sampler(extra=extra)
        s.tick()                     # the first sample has no rates: take it now, report the next
        time.sleep(min(every, 0.5))
    nxt = time.monotonic()
    while True:
        out(s.tick())
        nxt += every
        time.sleep(max(0.05, nxt - time.monotonic()))


def main(argv):
    cmd, args = (argv[0], argv[1:]) if argv else ("", [])
    try:
        if cmd == "glance":
            glance(float(args[0]) if args else 1.0)
        elif cmd == "watch":
            watch(float(args[0]) if args else 1.0)
        elif cmd == "once":
            s = FakeSampler() if fake() else Sampler(extra=dict(zip(("gpu", "gpu_apps"), read_gpu()), windows=read_windows()))
            out(s.tick())
        elif cmd == "signal" and len(args) in (2, 3):
            out(signal_pid(int(args[0]), args[1], "--force" in args[2:]))
        else:
            out({"ok": False, "error": "usage: tasks.py watch [SECONDS] | once | signal PID TERM|KILL|STOP|CONT [--force]"})
    except (BrokenPipeError, KeyboardInterrupt):
        pass
    except ValueError:
        out({"ok": False, "error": "Bad arguments."})


if __name__ == "__main__":
    main(sys.argv[1:])
